# frozen_string_literal: true

require "test_helper"

class TestGemSkill < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Gem::Skill::VERSION
  end

  def test_cache_root_is_in_home_dir
    assert_match(%r{\.gem/skills}, Gem::Skill::Cache::ROOT)
  end
end
