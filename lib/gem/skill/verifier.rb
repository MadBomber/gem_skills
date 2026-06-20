# frozen_string_literal: true

require "ruby_llm"

module Gem::Skill
  # Second-pass quality gate for a generated SKILL.md.
  #
  # Generation synthesizes prose sources (README, changelog, examples) which are
  # frequently wrong or stale about exact signatures. The verifier re-checks the
  # generated skill against the gem's ACTUAL source code — the only source of
  # truth — and corrects mismatched method signatures, default argument values,
  # visibility, return values, and behavioral claims.
  #
  # Whether the skill actually changed is decided by a deterministic diff of the
  # content before and after, not by trusting the model's self-report, so callers
  # can rely on #changed? for an exit code and a "fixed" flag.
  class Verifier
    BEGIN_MARK = "===BEGIN SKILL==="
    END_MARK   = "===END SKILL==="

    SYSTEM_INSTRUCTIONS = <<~SYSTEM
      You verify a generated Claude Code SKILL.md for a Ruby gem against the gem's
      ACTUAL SOURCE CODE. The source code is the only source of truth. READMEs,
      changelogs, and docstrings are frequently stale or wrong; when the SKILL.md
      disagrees with the source, the source always wins.

      Check every concrete claim against the source: method signatures, default
      argument values, keyword vs positional arguments, public/private/protected
      visibility, return values, constant and class/module names, default option
      values, and described runtime behavior (including what arguments a yielded
      block actually receives). Correct anything the source contradicts.

      Rules:
      - Do NOT invent APIs, methods, or options that are absent from the source.
      - Do NOT restructure, re-style, or "improve" content that is already correct.
        Preserve correct text verbatim so the diff stays minimal.
      - Only change what the source proves is wrong.
    SYSTEM

    PROMPT = <<~PROMPT
      Verify the SKILL.md below for "%<gem_name>s" v%<version>s against the gem's
      source code. Correct every claim the source contradicts.

      Output ONLY the full corrected SKILL.md in raw Markdown (even if you change
      nothing), wrapped exactly between these marker lines and with no other text:
      %<begin_mark>s
      <corrected SKILL.md here>
      %<end_mark>s

      ============================================================
      CURRENT SKILL.md
      ============================================================

      %<skill>s

      ============================================================
      GEM SOURCE CODE (ground truth)
      ============================================================

      %<source>s
    PROMPT

    # content:    the (possibly corrected) skill markdown
    # changed:    true iff content differs from the original (diff-based)
    # verifiable: false when no source was available to check against
    # model:      the model used for verification
    Result = Data.define(:content, :changed, :verifiable, :model) do
      def changed? = changed
    end

    attr_reader :gem_name, :version, :model

    def initialize(gem_name, version, model: Generator::DEFAULT_MODEL)
      @gem_name = gem_name
      @version  = version
      @model    = model
    end

    # Verify skill_content against the gem source. Returns a Result.
    def verify(skill_content)
      fetcher = Fetcher.new(gem_name, version)
      source  = fetcher.source_code
      if source.nil? || source.strip.empty?
        return Result.new(content: skill_content, changed: false, verifiable: false, model: model)
      end

      raw       = build_chat.ask(format_prompt(skill_content, source)).content.to_s
      # Re-apply frontmatter to both sides so the diff compares like-for-like and
      # the stored skill always keeps valid frontmatter, even if the model dropped it.
      original  = Frontmatter.build(gem_name, version, skill_content)
      corrected = Frontmatter.build(gem_name, version, extract_skill(raw, skill_content))
      changed   = normalize(corrected) != normalize(original)

      Result.new(content: (changed ? corrected : skill_content), changed: changed,
                 verifiable: true, model: model)
    rescue RubyLLM::Error => e
      raise Error, e.message
    end

    private

    def build_chat
      RubyLLM.chat(model: model).with_instructions(SYSTEM_INSTRUCTIONS)
    end

    def format_prompt(skill_content, source)
      format(
        PROMPT,
        gem_name:   gem_name,
        version:    version,
        begin_mark: BEGIN_MARK,
        end_mark:   END_MARK,
        skill:      skill_content,
        source:     source
      )
    end

    # Pull the corrected skill out from between the markers. If the model didn't
    # honor the protocol, fall back to the original so we never corrupt the cache.
    def extract_skill(raw, fallback)
      start = raw.index(BEGIN_MARK)
      return fallback unless start

      body = raw[(start + BEGIN_MARK.length)..]
      stop = body.index(END_MARK)
      body = body[0...stop] if stop

      body = body.to_s.strip
      body.empty? ? fallback : body
    end

    def normalize(text)
      text.to_s.gsub(/[ \t]+$/, "").strip
    end
  end
end
