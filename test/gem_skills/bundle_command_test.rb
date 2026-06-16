# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gem_skills/cli/bundle_command"

class BundlerCommandTest < Minitest::Test
  FAKE_GEMS = { "my_gem" => "1.0.0", "other_gem" => "2.1.0" }.freeze

  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
    @output = StringIO.new
    $stdout = @output
  end

  def teardown
    $stdout = STDOUT
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
  end

  # --- option parsing ---

  def test_parse_options_force_flag
    opts, remaining = call_parse_options(%w[install --force])
    assert opts[:force]
    assert_equal %w[install], remaining
  end

  def test_parse_options_model_flag
    opts, rest = call_parse_options(%w[install --model claude-haiku-4-5])
    assert_equal "claude-haiku-4-5", opts[:model]
  end

  def test_parse_options_no_flags
    opts, rest = call_parse_options(%w[install])
    refute opts[:force]
    assert_nil opts[:model]
    assert_equal %w[install], rest
  end

  # --- install ---

  def test_install_skips_already_cached_gems
    pre_cache_gems
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        GemSkills::BundlerCommand.install
      end
    end
    assert_match "skip", @output.string
  end

  def test_install_generates_uncached_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        GemSkills::Generator.stub(:new, ->(*args, **) {
          fake_gen(generated, args[0])
        }) do
          GemSkills::BundlerCommand.install
        end
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_force_regenerates_cached_gems
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        GemSkills::Generator.stub(:new, ->(*args, **) {
          fake_gen(generated, args[0])
        }) do
          GemSkills::BundlerCommand.install(force: true)
        end
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_reports_error_and_continues_on_failure
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        call_count = 0
        GemSkills::Generator.stub(:new, ->(*args, **) {
          call_count += 1
          failing_gen(args[0])
        }) do
          GemSkills::BundlerCommand.install
        end
      end
    end
    assert_match "✗", @output.string
    assert_match "Errors:", @output.string
  end

  # --- refresh ---

  def test_refresh_skips_gems_already_at_correct_version
    pre_cache_gems
    stub_lockfile(FAKE_GEMS) do
      stub_linker(linked: FAKE_GEMS) do
        GemSkills::BundlerCommand.refresh
      end
    end
    assert_match "ok", @output.string
    refute_match "gen", @output.string
  end

  def test_refresh_updates_gems_with_changed_version
    stub_cache("my_gem", "1.0.0", "old skill")
    stub_lockfile({ "my_gem" => "1.1.0" }) do
      stub_linker(linked: { "my_gem" => "1.0.0" }) do
        GemSkills::Generator.stub(:new, ->(*args, **) { fake_gen([], args[0]) }) do
          GemSkills::BundlerCommand.refresh
        end
      end
    end
    assert_match "update", @output.string
  end

  # --- list ---

  def test_list_shows_linked_gems
    stub_linker(linked: FAKE_GEMS) do
      GemSkills::BundlerCommand.list
    end
    assert_match "my_gem", @output.string
    assert_match "other_gem", @output.string
  end

  def test_list_shows_empty_message_when_none_linked
    stub_linker(linked: {}) do
      GemSkills::BundlerCommand.list
    end
    assert_match "No skills linked", @output.string
  end

  private

  def call_parse_options(args)
    GemSkills::BundlerCommand.send(:parse_options, args)
  end

  def pre_cache_gems
    FAKE_GEMS.each { |name, ver| stub_cache(name, ver, "# #{name} skill") }
  end

  def stub_cache(name, ver, content)
    dir = File.join(@tmpdir, name, ver)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), content)
  end

  def stub_lockfile(gems)
    GemSkills::Lockfile.stub(:gems, gems) { yield }
  end

  def stub_linker(linked: {})
    entries = linked.map { |name, ver| { gem_name: name, version: ver, valid: true } }
    GemSkills::Linker.stub(:link,           ->(*) {}) do
      GemSkills::Linker.stub(:prune_dead_links, ->(*) {}) do
        GemSkills::Linker.stub(:linked_gems,    entries) do
          yield
        end
      end
    end
  end

  def fake_gen(log, gem_name)
    gen = Object.new
    gen.define_singleton_method(:generate) do |**|
      log << gem_name
      "# #{gem_name} skill"
    end
    gen
  end

  def failing_gen(gem_name)
    gen = Object.new
    gen.define_singleton_method(:generate) { |**| raise GemSkills::Error, "no docs found" }
    gen
  end

  def stub_cache_root(dir)
    @original_root = GemSkills::Cache::ROOT
    GemSkills::Cache.send(:remove_const, :ROOT)
    GemSkills::Cache.const_set(:ROOT, dir)
  end

  def restore_cache_root
    GemSkills::Cache.send(:remove_const, :ROOT)
    GemSkills::Cache.const_set(:ROOT, @original_root)
  end
end
