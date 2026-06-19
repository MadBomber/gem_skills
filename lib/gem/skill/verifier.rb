# frozen_string_literal: true

require "ruby_llm"
require "json"

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
  # can rely on #changed? for an exit code.
  #
  # Each correction is returned as a structured Hash (see CHANGE_KEYS) detailed
  # enough to file a documentation issue against the gem.
  class Verifier
    BEGIN_MARK = "===BEGIN SKILL==="
    END_MARK   = "===END SKILL==="

    # The fields every change Hash carries. Designed to be issue-ready: who is
    # wrong, where, what it said, what it should say, and the source proof.
    CHANGE_KEYS = %w[category symbol skill_section source_location was now detail source_evidence].freeze

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

      Output EXACTLY these two parts and nothing else:

      PART 1 — a line "CHANGES_JSON:" followed by a JSON array of the corrections
      you made. Use [] if nothing was wrong. Each array element is an object with
      these string keys:
        - "category": one of "signature", "default_value", "visibility",
          "return_value", "behavior", "naming", "removed_api", "other"
        - "symbol": the affected API, e.g. "TTY::Spinner#stop" or "FOO_CONST"
        - "skill_section": the SKILL.md section the error appeared in, e.g. "Core API"
        - "source_location": the source file and (if known) line, e.g.
          "lib/tty/spinner.rb:387"
        - "was": the incorrect text exactly as it appeared in the SKILL.md
        - "now": the corrected text
        - "detail": one sentence a maintainer could read as a doc-bug report
        - "source_evidence": the minimal source snippet that proves the correction

      PART 2 — the full corrected SKILL.md in raw Markdown (even if unchanged),
      wrapped exactly between these marker lines:
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
    # changes:    array of issue-ready change Hashes (see CHANGE_KEYS)
    # changed:    true iff content differs from the original (diff-based)
    # verifiable: false when no source was available to check against
    # source:     provenance Hash from Fetcher#source_manifest (or nil)
    # model:      the model used for verification
    Result = Data.define(:content, :changes, :changed, :verifiable, :source, :model) do
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
        return Result.new(content: skill_content, changes: [], changed: false,
                          verifiable: false, source: nil, model: model)
      end

      raw       = build_chat.ask(format_prompt(skill_content, source)).content.to_s
      # Re-apply frontmatter to both sides so the diff compares like-for-like and
      # the stored skill always keeps valid frontmatter, even if the model dropped it.
      original  = Frontmatter.build(gem_name, version, skill_content)
      corrected = Frontmatter.build(gem_name, version, extract_skill(raw, skill_content))
      changed   = normalize(corrected) != normalize(original)
      changes   = changed ? changes_from(raw) : []

      Result.new(content: (changed ? corrected : skill_content), changes: changes, changed: changed,
                 verifiable: true, source: fetcher.source_manifest, model: model)
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

    # Parse the structured change list from the CHANGES_JSON section (everything
    # before the BEGIN marker). Returns normalized Hashes. When the content
    # changed but no parseable details were returned, emit one fallback entry so
    # the change is never silently undocumented.
    def changes_from(raw)
      head    = raw.split(BEGIN_MARK, 2).first.to_s
      array   = head[/\[.*\]/m]
      parsed  = array ? JSON.parse(array) : []
      changes = parsed.is_a?(Array) ? parsed.filter_map { |c| normalize_change(c) } : []
      changes.empty? ? [unspecified_change] : changes
    rescue JSON::ParserError
      [unspecified_change]
    end

    def normalize_change(change)
      return nil unless change.is_a?(Hash)

      stringified = change.transform_keys(&:to_s)
      CHANGE_KEYS.to_h { |key| [key, stringified[key].to_s] }
    end

    def unspecified_change
      normalize_change(
        "category" => "unspecified",
        "detail"   => "The verifier corrected the skill against source but did not return itemized change details."
      )
    end

    def normalize(text)
      text.to_s.gsub(/[ \t]+$/, "").strip
    end
  end
end
