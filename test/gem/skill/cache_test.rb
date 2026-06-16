# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CacheTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_root = Gem::Skill::Cache::ROOT
    Gem::Skill::Cache.instance_variable_set(:@root, @tmpdir) rescue nil
    # Override ROOT constant for tests
    @cache_root = @tmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_skill_path_structure
    path = Gem::Skill::Cache.skill_path("my_gem", "1.2.3")
    assert_match %r{my_gem/1\.2\.3/SKILL\.md}, path
  end

  def test_cached_returns_false_when_missing
    refute Gem::Skill::Cache.cached?("no_gem", "0.0.1")
  end

  def test_store_and_read_roundtrip
    with_tmp_cache do
      Gem::Skill::Cache.store("my_gem", "1.0.0", "# skill content")
      assert Gem::Skill::Cache.cached?("my_gem", "1.0.0")
      assert_equal "# skill content", Gem::Skill::Cache.read("my_gem", "1.0.0")
    end
  end

  def test_versions_lists_cached_versions
    with_tmp_cache do
      Gem::Skill::Cache.store("my_gem", "1.0.0", "v1")
      Gem::Skill::Cache.store("my_gem", "2.0.0", "v2")
      assert_equal %w[1.0.0 2.0.0], Gem::Skill::Cache.versions("my_gem").sort
    end
  end

  def test_purge_removes_version_dir
    with_tmp_cache do
      Gem::Skill::Cache.store("my_gem", "1.0.0", "content")
      Gem::Skill::Cache.purge("my_gem", "1.0.0")
      refute Gem::Skill::Cache.cached?("my_gem", "1.0.0")
    end
  end

  def test_read_raises_when_not_cached
    with_tmp_cache do
      assert_raises(Gem::Skill::Error) { Gem::Skill::Cache.read("missing_gem", "0.0.1") }
    end
  end

  def test_store_writes_metadata_json
    with_tmp_cache do
      Gem::Skill::Cache.store("my_gem", "1.0.0", "# skill", { model: "claude-sonnet-4-6" })
      meta_path = Gem::Skill::Cache.metadata_path("my_gem", "1.0.0")
      assert File.exist?(meta_path)
      meta = JSON.parse(File.read(meta_path))
      assert_equal "my_gem",            meta["gem_name"]
      assert_equal "1.0.0",             meta["version"]
      assert_equal "claude-sonnet-4-6", meta["model"]
      assert meta.key?("generated_at")
    end
  end

  def test_all_gems_returns_sorted_gem_names
    with_tmp_cache do
      Gem::Skill::Cache.store("zeitwerk", "2.0.0", "z skill")
      Gem::Skill::Cache.store("faraday",  "1.0.0", "f skill")
      assert_equal %w[faraday zeitwerk], Gem::Skill::Cache.all_gems
    end
  end

  private

  def with_tmp_cache
    stub_const(Gem::Skill::Cache, :ROOT, @tmpdir) { yield }
  end

  def stub_const(mod, name, value)
    old = mod.const_get(name)
    mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, old)
  end
end
