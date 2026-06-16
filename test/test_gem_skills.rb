# frozen_string_literal: true

require "test_helper"

class TestGemSkills < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::GemSkills::VERSION
  end

  def test_cache_root_is_in_home_dir
    assert_match(/\.gem_skills/, GemSkills::Cache::ROOT)
  end
end
