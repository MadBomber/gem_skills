# frozen_string_literal: true

require "test_helper"
require "json"

class VerifierTest < Minitest::Test
  ORIGINAL = "# tty-spinner v0.9.3\n\nstop(message = nil)"
  SOURCE   = "### lib/tty/spinner.rb\n\n```ruby\ndef stop(stop_message = '')\nend\n```"
  MANIFEST = { files: ["lib/tty/spinner.rb"], chars: 64, truncated: false }.freeze

  FakeResponse = Struct.new(:content)

  def setup
    @gem_name = "tty-spinner"
    @version  = "0.9.3"
  end

  def test_returns_unverifiable_when_no_source
    stub_fetcher(source: nil) do
      # LLM must not be called when there's nothing to verify against
      RubyLLM.stub(:chat, ->(*) { raise "should not call LLM" }) do
        result = verifier.verify(ORIGINAL)
        refute result.verifiable
        refute result.changed?
        assert_equal ORIGINAL, result.content
        assert_empty result.changes
        assert_nil result.source
      end
    end
  end

  def test_detects_and_applies_structured_corrections
    corrected = "# tty-spinner v0.9.3\n\nstop(message = '')"
    change = {
      "category"        => "default_value",
      "symbol"          => "TTY::Spinner#stop",
      "skill_section"   => "Core API",
      "source_location" => "lib/tty/spinner.rb:387",
      "was"             => "stop(message = nil)",
      "now"             => "stop(message = '')",
      "detail"          => "Default argument is an empty string, not nil.",
      "source_evidence" => "def stop(stop_message = '')"
    }
    llm_output = <<~OUT
      CHANGES_JSON:
      #{JSON.generate([change])}

      #{Gem::Skill::Verifier::BEGIN_MARK}
      #{corrected}
      #{Gem::Skill::Verifier::END_MARK}
    OUT

    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      RubyLLM.stub(:chat, responding_chat(llm_output)) do
        result = verifier.verify(ORIGINAL)
        assert result.verifiable
        assert result.changed?
        assert result.content.start_with?("---\n"), "verified content should carry frontmatter"
        assert_includes result.content, "stop(message = '')"
        assert_equal 1, result.changes.size
        assert_equal change, result.changes.first
        assert_equal MANIFEST, result.source
        assert_equal Gem::Skill::Verifier::CHANGE_KEYS.sort, result.changes.first.keys.sort
      end
    end
  end

  def test_normalizes_partial_change_objects_to_full_key_set
    llm_output = <<~OUT
      CHANGES_JSON:
      [{"category":"signature","symbol":"X#y"}]

      #{Gem::Skill::Verifier::BEGIN_MARK}
      changed content here
      #{Gem::Skill::Verifier::END_MARK}
    OUT

    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      RubyLLM.stub(:chat, responding_chat(llm_output)) do
        change = verifier.verify(ORIGINAL).changes.first
        assert_equal Gem::Skill::Verifier::CHANGE_KEYS.sort, change.keys.sort
        assert_equal "signature", change["category"]
        assert_equal "X#y", change["symbol"]
        assert_equal "", change["detail"], "missing keys default to empty string"
      end
    end
  end

  def test_emits_fallback_change_when_content_changed_but_no_details
    llm_output = <<~OUT
      CHANGES_JSON:
      []

      #{Gem::Skill::Verifier::BEGIN_MARK}
      totally different content
      #{Gem::Skill::Verifier::END_MARK}
    OUT

    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      RubyLLM.stub(:chat, responding_chat(llm_output)) do
        result = verifier.verify(ORIGINAL)
        assert result.changed?
        assert_equal 1, result.changes.size
        assert_equal "unspecified", result.changes.first["category"]
      end
    end
  end

  def test_reports_no_change_when_content_identical
    llm_output = <<~OUT
      CHANGES_JSON:
      []

      #{Gem::Skill::Verifier::BEGIN_MARK}
      #{ORIGINAL}
      #{Gem::Skill::Verifier::END_MARK}
    OUT

    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      RubyLLM.stub(:chat, responding_chat(llm_output)) do
        result = verifier.verify(ORIGINAL)
        assert result.verifiable
        refute result.changed?
        assert_equal ORIGINAL, result.content
        assert_empty result.changes
      end
    end
  end

  def test_falls_back_to_original_when_markers_missing
    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      RubyLLM.stub(:chat, responding_chat("garbage with no markers at all")) do
        result = verifier.verify(ORIGINAL)
        refute result.changed?
        assert_equal ORIGINAL, result.content
      end
    end
  end

  def test_wraps_ruby_llm_error
    stub_fetcher(source: SOURCE, manifest: MANIFEST) do
      fake_chat = Object.new
      fake_chat.define_singleton_method(:with_instructions) { |_| self }
      fake_chat.define_singleton_method(:ask) { |_| raise RubyLLM::UnauthorizedError, "bad key" }
      RubyLLM.stub(:chat, fake_chat) do
        error = assert_raises(Gem::Skill::Error) { verifier.verify(ORIGINAL) }
        assert_match "bad key", error.message
      end
    end
  end

  private

  def verifier
    Gem::Skill::Verifier.new(@gem_name, @version)
  end

  def stub_fetcher(source:, manifest: nil)
    fetcher = Object.new
    fetcher.define_singleton_method(:source_code)     { source }
    fetcher.define_singleton_method(:source_manifest) { manifest }
    Gem::Skill::Fetcher.stub(:new, ->(*) { fetcher }) { yield }
  end

  def responding_chat(content)
    chat = Object.new
    chat.define_singleton_method(:with_instructions) { |_| self }
    chat.define_singleton_method(:ask) { |_| FakeResponse.new(content) }
    chat
  end
end
