# frozen_string_literal: true

require_relative "skill/version"
require_relative "skill/cache"
require_relative "skill/fetcher"
require_relative "skill/generator"
require_relative "skill/linker"
require_relative "skill/lockfile"

module Gem::Skill
  class Error < StandardError; end

  ENV_KEY_MAP = {
    anthropic_api_key:  "ANTHROPIC_API_KEY",
    openai_api_key:     "OPENAI_API_KEY",
    gemini_api_key:     "GEMINI_API_KEY",
    mistral_api_key:    "MISTRAL_API_KEY",
    deepseek_api_key:   "DEEPSEEK_API_KEY",
    openrouter_api_key: "OPENROUTER_API_KEY",
    xai_api_key:        "XAI_API_KEY"
  }.freeze

  # Configure RubyLLM from environment variables. Called automatically by the
  # CLI commands so users don't need a separate initializer for standalone use.
  # No-op if RubyLLM is already configured (e.g. in a Rails app).
  def self.configure_llm!
    RubyLLM.configure do |config|
      ENV_KEY_MAP.each do |attr, env_var|
        value = ENV[env_var]
        config.public_send(:"#{attr}=", value) if value
      end
    end
  end
end
