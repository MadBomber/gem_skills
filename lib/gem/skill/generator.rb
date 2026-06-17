# frozen_string_literal: true

require "ruby_llm"

module Gem::Skill
  # Drives the LLM pipeline: fetches docs, generates a SKILL.md, caches it.
  class Generator
    DEFAULT_MODEL = ENV.fetch("GEMSKILL_MODEL", "gpt-5.5")
    MAX_SOURCE_CHARS = 60_000  # guard against enormous READMEs blowing the context window

    SYSTEM_INSTRUCTIONS = <<~SYSTEM
      You are a Ruby gem documentation specialist who generates Claude Code skill files.
      A skill file gives Claude Code deep, practical knowledge about a library so it can
      use it correctly without re-reading source docs. Be accurate, concise, and complete
      for the most common use cases. No filler, no marketing language.
    SYSTEM

    SKILL_PROMPT = <<~PROMPT
      Generate a SKILL.md for the Ruby gem "%<gem_name>s" version %<version>s.

      Output raw Markdown directly. Do NOT wrap the output in a code fence or any
      other container — the file is Markdown, so no ```markdown wrapper.

      Begin immediately with the first section heading. Use exactly these sections:

      ## Overview
      One paragraph: what the gem does and when to reach for it.

      ## Installation
      Exact Gemfile/gemspec lines and any required post-install steps.

      ## Core API
      The most important classes, methods, and options. Show real method signatures
      and return values. Prefer code over prose.

      ## Common Patterns
      The 3-5 most frequent real-world usage patterns with working code examples.

      ## Gotchas & Edge Cases
      Things that surprise developers: unexpected defaults, version-specific behavior,
      thread safety concerns, performance cliffs, encoding issues.

      ## Configuration
      Initializer patterns, environment variables, defaults worth knowing.

      ## Testing
      How to test code that uses this gem: mocks, fakes, fixtures, VCR patterns.

      Synthesize the sources below — do not copy them verbatim.
      Write as a knowledgeable colleague, not a marketing document.

      ---

      %<sources>s
    PROMPT

    attr_reader :gem_name, :version, :model

    def initialize(gem_name, version, model: DEFAULT_MODEL)
      @gem_name = gem_name
      @version  = version
      @model    = model
    end

    # Generate and cache a SKILL.md. Returns the skill content string.
    # Pass a block to stream output chunks to the caller for live feedback.
    def generate(force: false, &block)
      return Cache.read(gem_name, version) if Cache.cached?(gem_name, version) && !force

      sources = Fetcher.new(gem_name, version).fetch_all
      raise Error, "No documentation found for #{gem_name} #{version}" if sources.empty?

      skill_content = block ? call_llm_streaming(sources, &block) : call_llm(sources)
      Cache.store(gem_name, version, skill_content, { sources: sources.keys.map(&:to_s), model: model })
      skill_content
    rescue RubyLLM::Error => e
      raise Error, e.message
    end

    private

    def call_llm(sources)
      chat = build_chat
      response = chat.ask(format_prompt(sources))
      strip_wrapper_fence(response.content)
    end

    def call_llm_streaming(sources)
      content = +""
      chat = build_chat
      chat.ask(format_prompt(sources)) do |chunk|
        text = chunk.content.to_s
        next if text.empty?

        yield text
        content << text
      end
      strip_wrapper_fence(content)
    end

    # Removes a leading ```markdown (or ```) fence and its closing ```.
    # Belt-and-suspenders: the prompt instructs the model not to wrap,
    # but some models do it anyway.
    def strip_wrapper_fence(content)
      content
        .sub(/\A\s*```(?:markdown)?\s*\n/, "")
        .sub(/\n```\s*\z/, "")
        .strip
    end

    def build_chat
      RubyLLM.chat(model: model).with_instructions(SYSTEM_INSTRUCTIONS)
    end

    def format_prompt(sources)
      formatted = sources.map do |name, content|
        body = content.length > MAX_SOURCE_CHARS ? "#{content[0, MAX_SOURCE_CHARS]}\n[... truncated ...]" : content
        "### #{name.to_s.upcase}\n\n#{body}"
      end.join("\n\n---\n\n")

      format(SKILL_PROMPT, gem_name: gem_name, version: version, sources: formatted)
    end
  end
end
