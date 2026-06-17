# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gem/skill/cli/bundle_command"

class BundlerCommandTest < Minitest::Test
  FAKE_GEMS = { "my_gem" => "1.0.0", "other_gem" => "2.1.0" }.freeze

  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
    @output = StringIO.new
    @errors = StringIO.new
    $stdout = @output
    $stderr = @errors
  end

  def teardown
    $stdout = STDOUT
    $stderr = STDERR
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
    opts, _rest = call_parse_options(%w[install --model claude-haiku-4-5])
    assert_equal "claude-haiku-4-5", opts[:model]
  end

  def test_parse_options_no_flags
    opts, rest = call_parse_options(%w[install])
    refute opts[:force]
    assert_nil opts[:model]
    assert_equal %w[install], rest
  end

  # --- install ---

  def test_install_skips_generation_when_already_cached
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_empty generated
  end

  def test_install_generates_uncached_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_generates_multiple_gems_concurrently
    generated = []
    gems = { "gem_a" => "1.0.0", "gem_b" => "2.0.0", "gem_c" => "3.0.0" }
    stub_lockfile(gems) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_equal gems.keys.sort, generated.sort
  end

  def test_install_force_regenerates_cached_gems
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        stub_generator(generated) { Gem::Skill::BundlerCommand.install(force: true) }
      end
    end
    assert_equal FAKE_GEMS.keys.sort, generated.sort
  end

  def test_install_continues_after_one_gem_fails
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        Gem::Skill::Generator.stub(:new, ->(name, *) {
          name == "my_gem" ? failing_gen : fake_gen(generated, name)
        }) { Gem::Skill::BundlerCommand.install }
      end
    end
    assert_includes generated, "other_gem"
    assert_match "my_gem", @errors.string
  end

  def test_install_reports_errors_to_stderr
    stub_lockfile(FAKE_GEMS) do
      stub_linker do
        Gem::Skill::Generator.stub(:new, ->(*) { failing_gen }) do
          Gem::Skill::BundlerCommand.install
        end
      end
    end
    assert_match "Errors", @errors.string
  end

  def test_install_passes_custom_model_to_generator
    captured = {}
    gen_obj  = fake_gen([], "my_gem")
    stub_lockfile({ "my_gem" => "1.0.0" }) do
      stub_linker do
        Gem::Skill::Generator.stub(:new, ->(*args, **kwargs) { captured.merge!(kwargs); gen_obj }) do
          Gem::Skill::BundlerCommand.install(model: "claude-haiku-4-5")
        end
      end
    end
    assert_equal "claude-haiku-4-5", captured[:model]
  end

  # --- refresh ---

  def test_refresh_skips_gems_already_at_correct_version
    pre_cache_gems
    generated = []
    stub_lockfile(FAKE_GEMS) do
      stub_linker(linked: FAKE_GEMS) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_empty generated
  end

  def test_refresh_updates_gems_with_changed_version
    stub_cache("my_gem", "1.0.0", "old skill")
    generated = []
    stub_lockfile({ "my_gem" => "1.1.0" }) do
      stub_linker(linked: { "my_gem" => "1.0.0" }) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_includes generated, "my_gem"
  end

  def test_refresh_generates_new_gems_not_yet_linked
    generated = []
    stub_lockfile({ "new_gem" => "1.0.0" }) do
      stub_linker(linked: {}) do
        stub_generator(generated) { Gem::Skill::BundlerCommand.refresh }
      end
    end
    assert_includes generated, "new_gem"
  end

  # --- list ---

  def test_list_shows_linked_gems
    stub_linker(linked: FAKE_GEMS) do
      Gem::Skill::BundlerCommand.list
    end
    assert_match "my_gem", @output.string
    assert_match "other_gem", @output.string
  end

  def test_list_shows_empty_message_when_none_linked
    stub_linker(linked: {}) do
      Gem::Skill::BundlerCommand.list
    end
    assert_match "No skills linked", @output.string
  end

  private

  def call_parse_options(args)
    Gem::Skill::BundlerCommand.send(:parse_options, args)
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
    Gem::Skill::Lockfile.stub(:gems, gems) { yield }
  end

  def stub_linker(linked: {})
    entries = linked.map { |name, ver| { gem_name: name, version: ver, valid: true } }
    Gem::Skill::Linker.stub(:link,             ->(*) {}) do
      Gem::Skill::Linker.stub(:prune_dead_links, ->(*) {}) do
        Gem::Skill::Linker.stub(:linked_gems,    entries) do
          yield
        end
      end
    end
  end

  def stub_generator(generated)
    Gem::Skill::Generator.stub(:new, ->(name, *) { fake_gen(generated, name) }) { yield }
  end

  def fake_gen(log, gem_name)
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| log << gem_name; "# #{gem_name} skill" }
    obj
  end

  def failing_gen
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| raise Gem::Skill::Error, "no docs found" }
    obj
  end

  def stub_cache_root(dir)
    @original_root = Gem::Skill::Cache::ROOT
    Gem::Skill::Cache.send(:remove_const, :ROOT)
    Gem::Skill::Cache.const_set(:ROOT, dir)
  end

  def restore_cache_root
    Gem::Skill::Cache.send(:remove_const, :ROOT)
    Gem::Skill::Cache.const_set(:ROOT, @original_root)
  end
end
