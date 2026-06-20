# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Gem::Skill
  # Fetches documentation for a gem from multiple sources, in priority order:
  #   1. Local gem installation (Gem::Specification) — metadata + README + CHANGELOG + examples
  #   2. RubyGems API — metadata only, when gem isn't installed locally
  #   3. GitHub raw README — when gem isn't installed locally
  class Fetcher
    RUBYGEMS_API  = "https://rubygems.org/api/v1/gems/%s.json"
    GITHUB_RAW    = "https://raw.githubusercontent.com/%s/%s/%s"
    MAX_REDIRECTS = 5
    OPEN_TIMEOUT  = 5
    READ_TIMEOUT  = 10

    README_CANDIDATES    = %w[README.md README.rdoc README.txt README].freeze
    CHANGELOG_CANDIDATES = %w[CHANGELOG.md CHANGELOG.rdoc HISTORY.md CHANGES.md].freeze

    # Cap on concatenated source size handed to the verifier, to protect the
    # context window on large gems. Files are added whole until the cap is hit.
    SOURCE_MAX_CHARS = 150_000

    attr_reader :gem_name, :version

    def initialize(gem_name, version)
      @gem_name = gem_name
      @version  = version
    end

    # Returns a hash of source_name => content strings (only populated keys).
    def fetch_all
      {
        metadata:  metadata,
        readme:    readme,
        changelog: changelog,
        examples:  examples
      }.compact
    end

    def metadata
      @metadata ||= local_metadata || rubygems_metadata
    end

    def readme
      @readme ||= local_file(*README_CANDIDATES) || github_readme
    end

    def changelog
      @changelog ||= local_file(*CHANGELOG_CANDIDATES)
    end

    def examples
      @examples ||= local_examples
    end

    # The gem's actual Ruby source (lib/**/*.rb), concatenated with per-file
    # headers. This is the ground truth the verifier checks the skill against.
    # Returns nil when the gem isn't installed locally or has no lib sources —
    # verification is only possible against installed source.
    def source_code
      source_bundle&.fetch(:code)
    end

    private

    def source_bundle
      return @source_bundle if defined?(@source_bundle)

      @source_bundle = build_source_bundle
    end

    def build_source_bundle
      dir = gem_dir
      return nil unless dir

      lib = File.join(dir, "lib")
      return nil unless File.directory?(lib)

      files = Dir.glob(File.join(lib, "**", "*.rb")).sort
      return nil if files.empty?

      out       = +""
      included  = []
      truncated = false

      files.each do |path|
        relative = path.delete_prefix("#{dir}/")
        body     = File.read(path, encoding: "utf-8")
        chunk    = "### #{relative}\n\n```ruby\n#{body}\n```\n\n"
        if !out.empty? && out.length + chunk.length > SOURCE_MAX_CHARS
          truncated = true
          break
        end

        out << chunk
        included << relative
      end

      return nil if out.empty?

      { code: out, files: included, chars: out.length, truncated: truncated }
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      nil
    end

    # --- local gem spec ---

    def gem_spec
      @gem_spec ||= Gem::Specification.find_by_name(gem_name, version)
    rescue Gem::MissingSpecError, Gem::MissingSpecVersionError
      nil
    end

    def gem_dir
      @gem_dir ||= gem_spec&.gem_dir || locate_gem_dir
    end

    def locate_gem_dir
      dir_name = "#{gem_name}-#{version}"
      Gem.path.each do |base|
        path = File.join(base, "gems", dir_name)
        return path if File.directory?(path)
      end
      nil
    end

    def local_file(*candidates)
      dir = gem_dir
      return nil unless dir

      candidates.each do |name|
        path = File.join(dir, name)
        return File.read(path, encoding: "utf-8") if File.exist?(path)
      end
      nil
    end

    def local_metadata
      return nil unless gem_spec

      spec  = gem_spec
      lines = []
      lines << "**Gem:** #{spec.name} #{spec.version}"
      lines << "**Summary:** #{spec.summary}"                              if spec.summary.to_s.strip.length > 0
      lines << "**Description:** #{spec.description}"                     if spec.description.to_s.strip.length > 0
      lines << "**Author(s):** #{spec.authors.join(', ')}"                if spec.authors.any?
      lines << "**Homepage:** #{spec.homepage}"                           if spec.homepage.to_s.strip.length > 0
      lines << "**License(s):** #{spec.licenses.join(', ')}"              if spec.licenses.any?
      lines << "**Source:** #{spec.metadata['source_code_uri']}"          if spec.metadata["source_code_uri"]
      lines << "**Documentation:** #{spec.metadata['documentation_uri']}" if spec.metadata["documentation_uri"]

      runtime_deps = spec.runtime_dependencies
      if runtime_deps.any?
        dep_list = runtime_deps.map { |d| "#{d.name} (#{d.requirement})" }.join(", ")
        lines << "**Runtime dependencies:** #{dep_list}"
      end

      lines.join("\n")
    end

    def local_examples
      dir = gem_dir
      return nil unless dir

      examples_dir = File.join(dir, "examples")
      return nil unless File.directory?(examples_dir)

      files = Dir.glob(File.join(examples_dir, "**", "*.{rb,md}")).sort
      return nil if files.empty?

      files.map do |path|
        relative = path.delete_prefix("#{examples_dir}/")
        content  = File.read(path, encoding: "utf-8")
        "### #{relative}\n\n```\n#{content.strip}\n```"
      end.join("\n\n")
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      nil
    end

    # --- RubyGems API ---

    def rubygems_data
      @rubygems_data ||= begin
        body = fetch_url(format(RUBYGEMS_API, gem_name))
        body ? JSON.parse(body) : nil
      rescue JSON::ParserError
        nil
      end
    end

    def rubygems_metadata
      data = rubygems_data
      return nil unless data

      lines = []
      lines << "**Gem:** #{data['name']} #{data['version']}"
      lines << "**Summary:** #{data['info']}"                     if data["info"].to_s.strip.length > 0
      lines << "**Homepage:** #{data['homepage_uri']}"            if data["homepage_uri"]
      lines << "**Source:** #{data['source_code_uri']}"           if data["source_code_uri"]
      lines << "**Documentation:** #{data['documentation_uri']}"  if data["documentation_uri"]

      runtime_deps = data.dig("dependencies", "runtime") || []
      if runtime_deps.any?
        dep_list = runtime_deps.map { |d| "#{d['name']} (#{d['requirements']})" }.join(", ")
        lines << "**Runtime dependencies:** #{dep_list}"
      end

      lines.join("\n")
    end

    # --- GitHub raw README ---

    def github_readme
      repo = github_repo
      return nil unless repo

      README_CANDIDATES.each do |filename|
        %w[main master].each do |branch|
          url     = format(GITHUB_RAW, repo, branch, filename)
          content = fetch_url(url)
          return content if content
        end
      end
      nil
    end

    def github_repo
      data = rubygems_data
      return nil unless data

      candidate_uris = [data["source_code_uri"], data["homepage_uri"]].compact
      candidate_uris.each do |uri|
        match = uri.match(%r{github\.com[/:](?<owner>[^/]+)/(?<repo>[^/.\s]+?)(?:\.git)?(?:/|$)})
        return "#{match[:owner]}/#{match[:repo]}" if match
      end
      nil
    end

    # --- HTTP ---

    def fetch_url(url, redirects_left: MAX_REDIRECTS)
      return nil if redirects_left.zero?

      uri        = URI(url)
      uri.scheme = "https" if uri.scheme == "http"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.get(uri.request_uri, "User-Agent" => "gem-skill/#{Gem::Skill::VERSION}")
      end

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        fetch_url(response["location"], redirects_left: redirects_left - 1)
      end
    rescue StandardError
      nil
    end
  end
end
