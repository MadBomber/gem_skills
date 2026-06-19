# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class GeneratorTest < Minitest::Test
  FAKE_SKILL   = "# chunker-ruby 1.0.0\n\nA great skill."
  FAKE_SOURCES = { readme: "# Chunker\n\nChunks text into pieces." }.freeze

  FakeResponse = Struct.new(:content)

  def setup
    @tmpdir   = Dir.mktmpdir
    @gem_name = "chunker-ruby"
    @version  = "1.0.0"
    stub_cache_root(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
  end

  def test_generate_calls_llm_and_caches_result
    with_stubs(sources: FAKE_SOURCES, skill: FAKE_SKILL) do
      result = Gem::Skill::Generator.new(@gem_name, @version).generate
      assert result.start_with?("---\n"), "generated skill should start with frontmatter"
      assert_includes result, FAKE_SKILL, "original body should be preserved after the frontmatter"
      assert Gem::Skill::Cache.cached?(@gem_name, @version)
      assert_equal result, Gem::Skill::Cache.read(@gem_name, @version)
    end
  end

  def test_generate_adds_frontmatter_with_name_and_description
    with_stubs(sources: FAKE_SOURCES, skill: FAKE_SKILL) do
      result = Gem::Skill::Generator.new(@gem_name, @version).generate
      fm = result[/\A---\n(.*?)\n---/m, 1]
      assert fm, "expected a frontmatter block"
      assert_match(/^name:\s*chunker-ruby$/, fm)
      assert_match(/^description:\s*".+"$/, fm)
    end
  end

  def test_generate_hyphenates_underscore_gem_names_in_frontmatter
    with_stubs(sources: FAKE_SOURCES, skill: FAKE_SKILL) do
      result = Gem::Skill::Generator.new("ruby_llm", "1.0.0").generate
      assert_match(/^name:\s*ruby-llm$/, result[/\A---\n(.*?)\n---/m, 1])
    end
  end

  def test_generate_returns_cached_content_without_fetching
    Gem::Skill::Cache.store(@gem_name, @version, FAKE_SKILL)

    # Fetcher raises if called — proves it was skipped
    Gem::Skill::Fetcher.stub(:new, -> (*) { raise "should not fetch" }) do
      result = Gem::Skill::Generator.new(@gem_name, @version).generate
      assert_equal FAKE_SKILL, result
    end
  end

  def test_generate_force_bypasses_cache
    Gem::Skill::Cache.store(@gem_name, @version, "stale content")
    with_stubs(sources: FAKE_SOURCES, skill: FAKE_SKILL) do
      result = Gem::Skill::Generator.new(@gem_name, @version).generate(force: true)
      assert_includes result, FAKE_SKILL
      refute_includes result, "stale content"
    end
  end

  def test_generate_raises_when_no_sources_found
    with_stubs(sources: {}, skill: nil) do
      assert_raises(Gem::Skill::Error) do
        Gem::Skill::Generator.new(@gem_name, @version).generate
      end
    end
  end

  def test_generate_converts_ruby_llm_error_to_gem_skill_error
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |_| raise RubyLLM::UnauthorizedError, "Invalid API key" }

    Gem::Skill::Fetcher.stub(:new, fake_fetcher(FAKE_SOURCES)) do
      RubyLLM.stub(:chat, fake_chat) do
        error = assert_raises(Gem::Skill::Error) do
          Gem::Skill::Generator.new(@gem_name, @version).generate
        end
        assert_match "Invalid API key", error.message
      end
    end
  end

  def test_generate_streams_chunks_to_block
    chunks    = %w[## Overview\n Chunks\ text.]
    fake_chat = streaming_chat(chunks)

    Gem::Skill::Fetcher.stub(:new, fake_fetcher(FAKE_SOURCES)) do
      RubyLLM.stub(:chat, fake_chat) do
        received = []
        Gem::Skill::Generator.new(@gem_name, @version).generate { |c| received << c }
        assert_equal chunks, received
      end
    end
  end

  def test_strip_wrapper_fence_removes_markdown_fence
    gen = Gem::Skill::Generator.new(@gem_name, @version)
    wrapped = "```markdown\n## Overview\nDoes stuff.\n```"
    assert_equal "## Overview\nDoes stuff.", gen.send(:strip_wrapper_fence, wrapped)
  end

  def test_strip_wrapper_fence_removes_plain_fence
    gen = Gem::Skill::Generator.new(@gem_name, @version)
    wrapped = "```\n## Overview\nDoes stuff.\n```"
    assert_equal "## Overview\nDoes stuff.", gen.send(:strip_wrapper_fence, wrapped)
  end

  def test_strip_wrapper_fence_leaves_clean_content_untouched
    gen = Gem::Skill::Generator.new(@gem_name, @version)
    clean = "## Overview\nDoes stuff."
    assert_equal clean, gen.send(:strip_wrapper_fence, clean)
  end

  def test_custom_model_passed_to_ruby_llm
    captured_model = nil
    fake_chat      = responding_chat(FAKE_SKILL)
    capture_model  = ->(**kwargs) { captured_model = kwargs[:model]; fake_chat }

    Gem::Skill::Fetcher.stub(:new, fake_fetcher(FAKE_SOURCES)) do
      RubyLLM.stub(:chat, capture_model) do
        Gem::Skill::Generator.new(@gem_name, @version, model: "claude-haiku-4-5").generate
      end
    end

    assert_equal "claude-haiku-4-5", captured_model
  end

  private

  def with_stubs(sources:, skill:)
    fake_chat = skill ? responding_chat(skill) : nil
    Gem::Skill::Fetcher.stub(:new, fake_fetcher(sources)) do
      RubyLLM.stub(:chat, fake_chat) do
        yield
      end
    end
  end

  def fake_fetcher(sources)
    fetcher = Object.new
    fetcher.define_singleton_method(:fetch_all) { sources }
    ->(*) { fetcher }
  end

  def responding_chat(content)
    chat = Object.new
    chat.define_singleton_method(:with_instructions) { |_| self }
    chat.define_singleton_method(:ask) { |_| FakeResponse.new(content) }
    chat
  end

  def streaming_chat(chunks)
    chat = Object.new
    chat.define_singleton_method(:with_instructions) { |_| self }
    chat.define_singleton_method(:ask) do |_, &blk|
      chunks.each { |c| blk&.call(FakeResponse.new(c)) }
    end
    chat
  end

end
