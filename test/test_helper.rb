# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "gem/skill"

require "minitest/autorun"
require_relative "support/cache_helpers"

Minitest::Test.include CacheHelpers
