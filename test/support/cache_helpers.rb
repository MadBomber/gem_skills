# frozen_string_literal: true

module CacheHelpers
  def stub_cache_root(dir)
    @original_root = Gem::Skill::Cache::ROOT
    Gem::Skill::Cache.send(:remove_const, :ROOT)
    Gem::Skill::Cache.const_set(:ROOT, dir)
  end

  def restore_cache_root
    Gem::Skill::Cache.send(:remove_const, :ROOT)
    Gem::Skill::Cache.const_set(:ROOT, @original_root)
  end
end
