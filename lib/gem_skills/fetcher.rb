# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module GemSkills
  # Fetches documentation for a gem from multiple sources, in priority order:
  #   1. Local gem installation (Gem::Specification → gem_dir)
  #   2. RubyGems API (metadata, description, runtime deps)
  #   3. GitHub raw README (derived from source_code_uri / homepage_uri)
  class Fetcher
    RUBYGEMS_API  = "https://rubygems.org/api/v1/gems/%s.json"
    GITHUB_RAW    = "https://raw.githubusercontent.com/%s/%s/%s"
    MAX_REDIRECTS = 5
    OPEN_TIMEOUT  = 5
    READ_TIMEOUT  = 10

    README_CANDIDATES    = %w[README.md README.rdoc README.txt README].freeze
    CHANGELOG_CANDIDATES = %w[CHANGELOG.md CHANGELOG.rdoc HISTORY.md CHANGES.md].freeze

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
        changelog: changelog
      }.compact
    end

    def metadata
      @metadata ||= rubygems_metadata
    end

    def readme
      @readme ||= local_file(*README_CANDIDATES) || github_readme
    end

    def changelog
      @changelog ||= local_file(*CHANGELOG_CANDIDATES)
    end

    private

    # --- local gem spec ---

    def gem_spec
      @gem_spec ||= Gem::Specification.find_by_name(gem_name, version)
    rescue Gem::MissingSpecError, Gem::MissingSpecVersionError
      nil
    end

    def local_file(*candidates)
      return nil unless gem_spec

      candidates.each do |name|
        path = File.join(gem_spec.gem_dir, name)
        return File.read(path, encoding: "utf-8") if File.exist?(path)
      end
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
        http.get(uri.request_uri, "User-Agent" => "gem_skills/#{GemSkills::VERSION}")
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
