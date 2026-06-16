# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class FetcherTest < Minitest::Test
  def setup
    @gem_name = "chunker-ruby"
    @version  = "1.2.3"
    @fetcher  = Gem::Skill::Fetcher.new(@gem_name, @version)
  end

  # --- gem_dir / locate_gem_dir ---

  def test_gem_dir_returns_spec_gem_dir_when_available
    fake = Object.new
    fake.define_singleton_method(:gem_dir) { "/path/from/spec" }
    @fetcher.stub(:gem_spec, fake) do
      assert_equal "/path/from/spec", @fetcher.send(:gem_dir)
    end
  end

  def test_gem_dir_falls_back_to_path_search_when_no_spec
    Dir.mktmpdir do |base|
      gem_d = File.join(base, "gems", "#{@gem_name}-#{@version}")
      FileUtils.mkdir_p(gem_d)
      @fetcher.stub(:gem_spec, nil) do
        Gem.stub(:path, [base]) do
          assert_equal gem_d, @fetcher.send(:gem_dir)
        end
      end
    end
  end

  def test_locate_gem_dir_finds_directory_by_name_and_version
    Dir.mktmpdir do |base|
      gem_d = File.join(base, "gems", "chunker-ruby-1.2.3")
      FileUtils.mkdir_p(gem_d)
      Gem.stub(:path, [base]) do
        assert_equal gem_d, @fetcher.send(:locate_gem_dir)
      end
    end
  end

  def test_locate_gem_dir_returns_nil_when_not_found
    Gem.stub(:path, []) do
      assert_nil @fetcher.send(:locate_gem_dir)
    end
  end

  # --- local_file ---

  def test_local_readme_read_from_gem_dir
    with_fake_gem_dir do |dir|
      File.write(File.join(dir, "README.md"), "# Chunker\nDoes chunking.")
      readme = @fetcher.send(:local_file, "README.md")
      assert_equal "# Chunker\nDoes chunking.", readme
    end
  end

  def test_local_file_tries_candidates_in_order
    with_fake_gem_dir do |dir|
      File.write(File.join(dir, "README.rdoc"), "= Chunker")
      result = @fetcher.send(:local_file, "README.md", "README.rdoc")
      assert_equal "= Chunker", result
    end
  end

  def test_local_file_returns_nil_when_gem_not_found
    @fetcher.stub(:gem_dir, nil) do
      assert_nil @fetcher.send(:local_file, "README.md")
    end
  end

  def test_local_file_returns_nil_when_no_candidates_match
    with_fake_gem_dir do |_dir|
      assert_nil @fetcher.send(:local_file, "NONEXISTENT.md")
    end
  end

  # --- local_metadata ---

  def test_local_metadata_returns_nil_without_gem_spec
    @fetcher.stub(:gem_spec, nil) do
      assert_nil @fetcher.send(:local_metadata)
    end
  end

  def test_local_metadata_formats_core_fields
    @fetcher.stub(:gem_spec, fake_spec(summary: "Does chunking.", authors: ["Alice"],
                                       homepage: "https://example.com", licenses: ["MIT"])) do
      result = @fetcher.send(:local_metadata)
      assert_match "chunker-ruby 1.2.3", result
      assert_match "Does chunking.", result
      assert_match "Alice", result
      assert_match "https://example.com", result
      assert_match "MIT", result
    end
  end

  def test_local_metadata_includes_description_when_present
    @fetcher.stub(:gem_spec, fake_spec(description: "A longer explanation of chunking.")) do
      assert_match "longer explanation", @fetcher.send(:local_metadata)
    end
  end

  def test_local_metadata_includes_runtime_dependencies
    dep = Gem::Dependency.new("activesupport", "~> 7.0")
    @fetcher.stub(:gem_spec, fake_spec(runtime_dependencies: [dep])) do
      assert_match "activesupport (~> 7.0)", @fetcher.send(:local_metadata)
    end
  end

  def test_local_metadata_includes_spec_metadata_uris
    @fetcher.stub(:gem_spec, fake_spec(metadata: {
      "source_code_uri"   => "https://github.com/example/chunker-ruby",
      "documentation_uri" => "https://rubydoc.info/gems/chunker-ruby"
    })) do
      result = @fetcher.send(:local_metadata)
      assert_match "https://github.com/example/chunker-ruby", result
      assert_match "https://rubydoc.info/gems/chunker-ruby", result
    end
  end

  # --- metadata priority ---

  def test_metadata_prefers_local_spec_over_rubygems_api
    @fetcher.stub(:gem_spec, fake_spec(summary: "Local summary")) do
      # rubygems_data would make a network call; if local wins it never runs
      @fetcher.stub(:rubygems_data, -> { raise "should not hit rubygems.org" }) do
        result = @fetcher.metadata
        assert_match "Local summary", result
      end
    end
  end

  def test_metadata_falls_back_to_rubygems_api_when_no_local_spec
    @fetcher.stub(:gem_spec, nil) do
      stub_rubygems_data("name" => "chunker-ruby", "version" => "1.2.3",
                         "info" => "Remote summary", "dependencies" => {}) do
        assert_match "Remote summary", @fetcher.metadata
      end
    end
  end

  # --- RubyGems API (unit tests for the private method) ---

  def test_rubygems_metadata_formats_key_fields
    stub_rubygems_data(
      "name"              => "chunker-ruby",
      "version"           => "1.2.3",
      "info"              => "Chunks text into pieces.",
      "homepage_uri"      => "https://example.com",
      "source_code_uri"   => "https://github.com/example/chunker-ruby",
      "documentation_uri" => "https://rubydoc.info/gems/chunker-ruby",
      "dependencies"      => { "runtime" => [{ "name" => "activesupport", "requirements" => ">= 6.0" }] }
    ) do
      result = @fetcher.send(:rubygems_metadata)
      assert_match "chunker-ruby 1.2.3", result
      assert_match "Chunks text into pieces.", result
      assert_match "https://github.com/example/chunker-ruby", result
      assert_match "activesupport (>= 6.0)", result
    end
  end

  def test_rubygems_metadata_returns_nil_on_failed_fetch
    @fetcher.stub(:fetch_url, nil) do
      assert_nil @fetcher.send(:rubygems_metadata)
    end
  end

  def test_rubygems_metadata_returns_nil_on_bad_json
    @fetcher.stub(:fetch_url, "not json") do
      assert_nil @fetcher.send(:rubygems_metadata)
    end
  end

  # --- github_repo extraction ---

  def test_github_repo_parsed_from_source_code_uri
    stub_rubygems_data("source_code_uri" => "https://github.com/owner/my-gem") do
      assert_equal "owner/my-gem", @fetcher.send(:github_repo)
    end
  end

  def test_github_repo_falls_back_to_homepage_uri
    stub_rubygems_data(
      "source_code_uri" => nil,
      "homepage_uri"    => "https://github.com/owner/my-gem"
    ) do
      assert_equal "owner/my-gem", @fetcher.send(:github_repo)
    end
  end

  def test_github_repo_strips_dot_git_suffix
    stub_rubygems_data("source_code_uri" => "https://github.com/owner/my-gem.git") do
      assert_equal "owner/my-gem", @fetcher.send(:github_repo)
    end
  end

  def test_github_repo_returns_nil_for_non_github_uri
    stub_rubygems_data("source_code_uri" => "https://gitlab.com/owner/my-gem") do
      assert_nil @fetcher.send(:github_repo)
    end
  end

  def test_github_repo_returns_nil_when_no_metadata
    @fetcher.stub(:rubygems_data, nil) do
      assert_nil @fetcher.send(:github_repo)
    end
  end

  # --- fetch_url redirect following ---

  def test_fetch_url_returns_nil_when_redirect_limit_exhausted
    result = @fetcher.send(:fetch_url, "https://example.com", redirects_left: 0)
    assert_nil result
  end

  # --- examples ---

  def test_examples_returns_nil_when_gem_not_found
    @fetcher.stub(:gem_dir, nil) do
      assert_nil @fetcher.examples
    end
  end

  def test_examples_returns_nil_when_no_examples_dir
    with_fake_gem_dir do |_dir|
      assert_nil @fetcher.examples
    end
  end

  def test_examples_returns_nil_when_examples_dir_is_empty
    with_fake_gem_dir do |dir|
      FileUtils.mkdir_p(File.join(dir, "examples"))
      assert_nil @fetcher.examples
    end
  end

  def test_examples_reads_ruby_files
    with_fake_gem_dir do |dir|
      examples_dir = File.join(dir, "examples")
      FileUtils.mkdir_p(examples_dir)
      File.write(File.join(examples_dir, "basic.rb"), 'puts "hello"')
      result = @fetcher.examples
      assert_match "basic.rb", result
      assert_match 'puts "hello"', result
    end
  end

  def test_examples_reads_markdown_files
    with_fake_gem_dir do |dir|
      examples_dir = File.join(dir, "examples")
      FileUtils.mkdir_p(examples_dir)
      File.write(File.join(examples_dir, "guide.md"), "# Guide\n\nHow to use.")
      result = @fetcher.examples
      assert_match "guide.md", result
      assert_match "How to use", result
    end
  end

  def test_examples_labels_files_with_relative_path
    with_fake_gem_dir do |dir|
      examples_dir = File.join(dir, "examples")
      FileUtils.mkdir_p(File.join(examples_dir, "advanced"))
      File.write(File.join(examples_dir, "advanced", "nested.rb"), "# nested example")
      assert_match "advanced/nested.rb", @fetcher.examples
    end
  end

  # --- fetch_all integration ---

  def test_fetch_all_returns_only_populated_sources
    @fetcher.stub(:metadata,  "meta content") do
      @fetcher.stub(:readme,    nil) do
        @fetcher.stub(:changelog, nil) do
          @fetcher.stub(:examples, nil) do
            result = @fetcher.fetch_all
            assert_equal({ metadata: "meta content" }, result)
          end
        end
      end
    end
  end

  def test_fetch_all_combines_all_available_sources
    @fetcher.stub(:metadata,  "meta")     do
      @fetcher.stub(:readme,    "readme")   do
        @fetcher.stub(:changelog, "changes") do
          @fetcher.stub(:examples, "examples") do
            result = @fetcher.fetch_all
            assert_equal %i[metadata readme changelog examples], result.keys
          end
        end
      end
    end
  end

  private

  def with_fake_gem_dir
    tmpdir = Dir.mktmpdir
    @fetcher.stub(:gem_dir, tmpdir) { yield tmpdir }
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def stub_rubygems_data(data)
    @fetcher.stub(:rubygems_data, data) { yield }
  end

  def fake_spec(**attrs)
    defaults = {
      name: @gem_name, version: @version, summary: "", description: "",
      authors: [], homepage: "", licenses: [], metadata: {}, runtime_dependencies: []
    }
    spec = Object.new
    defaults.merge(attrs).each do |key, val|
      spec.define_singleton_method(key) { val }
    end
    spec
  end
end
