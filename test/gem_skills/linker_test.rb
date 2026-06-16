# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class LinkerTest < Minitest::Test
  def setup
    @project_dir  = Dir.mktmpdir
    @cache_dir    = Dir.mktmpdir
    stub_cache_root(@cache_dir)

    # Pre-populate a cached skill
    @gem_name = "my_gem"
    @version  = "1.0.0"
    skill_dir = File.join(@cache_dir, @gem_name, @version)
    FileUtils.mkdir_p(skill_dir)
    File.write(File.join(skill_dir, "SKILL.md"), "# My Gem Skill")
  end

  def teardown
    FileUtils.rm_rf(@project_dir)
    FileUtils.rm_rf(@cache_dir)
    restore_cache_root
  end

  def test_link_creates_symlink_in_claude_skills
    GemSkills::Linker.link(@gem_name, @version, @project_dir)
    link = File.join(@project_dir, ".claude", "skills", "#{@gem_name}.md")
    assert File.symlink?(link)
    assert File.exist?(link)
  end

  def test_link_replaces_existing_symlink
    GemSkills::Linker.link(@gem_name, @version, @project_dir)
    GemSkills::Linker.link(@gem_name, @version, @project_dir) # idempotent
    link = File.join(@project_dir, ".claude", "skills", "#{@gem_name}.md")
    assert File.symlink?(link)
  end

  def test_unlink_removes_symlink
    GemSkills::Linker.link(@gem_name, @version, @project_dir)
    GemSkills::Linker.unlink(@gem_name, @project_dir)
    link = File.join(@project_dir, ".claude", "skills", "#{@gem_name}.md")
    refute File.exist?(link)
  end

  def test_linked_gems_returns_entry
    GemSkills::Linker.link(@gem_name, @version, @project_dir)
    entries = GemSkills::Linker.linked_gems(@project_dir)
    assert_equal 1, entries.size
    assert_equal @gem_name, entries.first[:gem_name]
    assert_equal @version,  entries.first[:version]
    assert entries.first[:valid]
  end

  def test_prune_dead_links_removes_broken_symlinks
    GemSkills::Linker.link(@gem_name, @version, @project_dir)
    # Delete the cached skill to simulate a broken link
    FileUtils.rm_rf(File.join(@cache_dir, @gem_name))
    GemSkills::Linker.prune_dead_links(@project_dir)
    assert_empty GemSkills::Linker.linked_gems(@project_dir)
  end

  private

  def stub_cache_root(dir)
    @original_root = GemSkills::Cache::ROOT
    GemSkills::Cache.send(:remove_const, :ROOT)
    GemSkills::Cache.const_set(:ROOT, dir)
  end

  def restore_cache_root
    GemSkills::Cache.send(:remove_const, :ROOT)
    GemSkills::Cache.const_set(:ROOT, @original_root)
  end
end
