# frozen_string_literal: true

require "test_helper"

class VerifierTest < Minitest::Test
  ORIGINAL = "# tty-spinner v0.9.3\n\nstop(message = nil)"
  SOURCE   = "### lib/tty/spinner.rb\n\n```ruby\ndef stop(stop_message = '')\nend\n```"

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
      end
    end
  end

  def test_applies_correction_and_marks_changed
    corrected = "# tty-spinner v0.9.3\n\nstop(message = '')"
    stub_fetcher(source: SOURCE) do
      RubyLLM.stub(:chat, responding_chat(wrap(corrected))) do
        result = verifier.verify(ORIGINAL)
        assert result.verifiable
        assert result.changed?
        assert result.content.start_with?("---\n"), "verified content should carry frontmatter"
        assert_includes result.content, "stop(message = '')"
      end
    end
  end

  def test_reports_no_change_when_content_identical
    stub_fetcher(source: SOURCE) do
      RubyLLM.stub(:chat, responding_chat(wrap(ORIGINAL))) do
        result = verifier.verify(ORIGINAL)
        assert result.verifiable
        refute result.changed?
        assert_equal ORIGINAL, result.content
      end
    end
  end

  def test_falls_back_to_original_when_markers_missing
    stub_fetcher(source: SOURCE) do
      RubyLLM.stub(:chat, responding_chat("garbage with no markers at all")) do
        result = verifier.verify(ORIGINAL)
        refute result.changed?
        assert_equal ORIGINAL, result.content
      end
    end
  end

  def test_wraps_ruby_llm_error
    stub_fetcher(source: SOURCE) do
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

  # Wrap body in the marker protocol the verifier expects back from the model.
  def wrap(body)
    "#{Gem::Skill::Verifier::BEGIN_MARK}\n#{body}\n#{Gem::Skill::Verifier::END_MARK}\n"
  end

  def stub_fetcher(source:)
    fetcher = Object.new
    fetcher.define_singleton_method(:source_code) { source }
    Gem::Skill::Fetcher.stub(:new, ->(*) { fetcher }) { yield }
  end

  def responding_chat(content)
    chat = Object.new
    chat.define_singleton_method(:with_instructions) { |_| self }
    chat.define_singleton_method(:ask) { |_| FakeResponse.new(content) }
    chat
  end
end
