# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class FetcherTest < Minitest::Test
  def setup
    @gem_name = "chunker-ruby"
    @version  = "1.2.3"
    @fetcher  = GemSkills::Fetcher.new(@gem_name, @version)
  end

  # --- gem_spec / local files ---

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

  def test_local_file_returns_nil_when_no_spec
    @fetcher.stub(:gem_spec, nil) do
      assert_nil @fetcher.send(:local_file, "README.md")
    end
  end

  def test_local_file_returns_nil_when_no_candidates_match
    with_fake_gem_dir do |_dir|
      assert_nil @fetcher.send(:local_file, "NONEXISTENT.md")
    end
  end

  # --- RubyGems API ---

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
      result = @fetcher.metadata
      assert_match "chunker-ruby 1.2.3", result
      assert_match "Chunks text into pieces.", result
      assert_match "https://github.com/example/chunker-ruby", result
      assert_match "activesupport (>= 6.0)", result
    end
  end

  def test_rubygems_metadata_returns_nil_on_failed_fetch
    @fetcher.stub(:fetch_url, nil) do
      assert_nil @fetcher.metadata
    end
  end

  def test_rubygems_metadata_returns_nil_on_bad_json
    @fetcher.stub(:fetch_url, "not json") do
      assert_nil @fetcher.metadata
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

  # --- fetch_all integration ---

  def test_fetch_all_returns_only_populated_sources
    @fetcher.stub(:metadata,  "meta content") do
      @fetcher.stub(:readme,    nil) do
        @fetcher.stub(:changelog, nil) do
          result = @fetcher.fetch_all
          assert_equal({ metadata: "meta content" }, result)
        end
      end
    end
  end

  def test_fetch_all_combines_all_available_sources
    @fetcher.stub(:metadata,  "meta")     do
      @fetcher.stub(:readme,    "readme")   do
        @fetcher.stub(:changelog, "changes") do
          result = @fetcher.fetch_all
          assert_equal %i[metadata readme changelog], result.keys
        end
      end
    end
  end

  private

  def with_fake_gem_dir
    tmpdir = Dir.mktmpdir
    fake_spec = Object.new
    fake_spec.define_singleton_method(:gem_dir) { tmpdir }
    @fetcher.stub(:gem_spec, fake_spec) { yield tmpdir }
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def stub_rubygems_data(data)
    @fetcher.stub(:rubygems_data, data) { yield }
  end
end
