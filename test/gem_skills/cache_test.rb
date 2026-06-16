# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CacheTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_root = GemSkills::Cache::ROOT
    GemSkills::Cache.instance_variable_set(:@root, @tmpdir) rescue nil
    # Override ROOT constant for tests
    @cache_root = @tmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_skill_path_structure
    path = GemSkills::Cache.skill_path("my_gem", "1.2.3")
    assert_match %r{my_gem/1\.2\.3/SKILL\.md}, path
  end

  def test_cached_returns_false_when_missing
    refute GemSkills::Cache.cached?("no_gem", "0.0.1")
  end

  def test_store_and_read_roundtrip
    with_tmp_cache do
      GemSkills::Cache.store("my_gem", "1.0.0", "# skill content")
      assert GemSkills::Cache.cached?("my_gem", "1.0.0")
      assert_equal "# skill content", GemSkills::Cache.read("my_gem", "1.0.0")
    end
  end

  def test_versions_lists_cached_versions
    with_tmp_cache do
      GemSkills::Cache.store("my_gem", "1.0.0", "v1")
      GemSkills::Cache.store("my_gem", "2.0.0", "v2")
      assert_equal %w[1.0.0 2.0.0], GemSkills::Cache.versions("my_gem").sort
    end
  end

  def test_purge_removes_version_dir
    with_tmp_cache do
      GemSkills::Cache.store("my_gem", "1.0.0", "content")
      GemSkills::Cache.purge("my_gem", "1.0.0")
      refute GemSkills::Cache.cached?("my_gem", "1.0.0")
    end
  end

  private

  def with_tmp_cache
    stub_const(GemSkills::Cache, :ROOT, @tmpdir) { yield }
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
