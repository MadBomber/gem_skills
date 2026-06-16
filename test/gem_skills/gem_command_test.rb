# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gem_skills/cli/gem_command"

class GemCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
    @cmd    = Gem::Commands::SkillCommand.new
    @output = StringIO.new
    @errors = StringIO.new
    Gem.ui.instance_variable_set(:@outs, @output)
    Gem.ui.instance_variable_set(:@errs, @errors)
  end

  def teardown
    Gem.ui.instance_variable_set(:@outs, STDOUT)
    Gem.ui.instance_variable_set(:@errs, STDERR)
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
  end

  # --- execute dispatch ---

  def test_execute_shows_usage_for_nil_subcommand
    set_args
    GemSkills.stub(:configure_llm!, nil) { @cmd.execute }
    assert_match "install", @output.string
  end

  def test_execute_shows_usage_and_error_for_unknown_subcommand
    set_args("bogus")
    GemSkills.stub(:configure_llm!, nil) { @cmd.execute }
    assert_match "install", @output.string
    assert_match "Unknown subcommand", @errors.string
  end

  # --- cmd_install ---

  def test_install_raises_without_gem_name
    set_args
    assert_raises(Gem::CommandLineError) { @cmd.send(:cmd_install) }
  end

  def test_install_auto_installs_when_gem_not_present
    set_args("new_gem")
    generated = []
    @cmd.stub(:resolve_installed_version, nil) do
      @cmd.stub(:install_gem, "2.0.0") do
        stub_generator(generated) { @cmd.send(:cmd_install) }
      end
    end
    assert_includes generated, "new_gem"
    assert_match "not installed", @output.string
    assert_match "Cached", @output.string
  end

  def test_install_reports_error_when_auto_install_fails
    set_args("no_such_gem_xyz")
    @cmd.stub(:resolve_installed_version, nil) do
      @cmd.stub(:install_gem, ->(*) { raise GemSkills::Error, "Could not install 'no_such_gem_xyz'" }) do
        @cmd.send(:cmd_install)
      end
    end
    assert_match "Could not install", @errors.string
  end

  def test_install_shows_already_cached_message
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem", "1.0.0")
    @cmd.send(:cmd_install)
    assert_match "Already cached", @output.string
    assert_match "--force", @output.string
  end

  def test_install_generates_and_links_uncached_gem
    set_args("my_gem", "1.0.0")
    generated = []
    stub_generator(generated) { @cmd.send(:cmd_install) }
    assert_includes generated, "my_gem"
    assert_match "Cached", @output.string
  end

  def test_install_force_bypasses_cached_gem
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem", "1.0.0")
    set_option(:force, true)
    generated = []
    stub_generator(generated) { @cmd.send(:cmd_install) }
    assert_includes generated, "my_gem"
  end

  def test_install_passes_custom_model_to_generator
    set_args("my_gem", "1.0.0")
    set_option(:model, "claude-haiku-4-5")
    captured = {}
    gen_obj  = simple_generator
    GemSkills::Generator.stub(:new, ->(*_args, **kwargs) { captured.merge!(kwargs); gen_obj }) do
      @cmd.send(:cmd_install)
    end
    assert_equal "claude-haiku-4-5", captured[:model]
  end

  def test_install_rescues_gem_skills_error_and_reports_via_alert
    set_args("my_gem", "1.0.0")
    GemSkills::Generator.stub(:new, ->(*) { failing_generator }) do
      @cmd.send(:cmd_install)  # must not raise
    end
    assert_match "no docs found", @errors.string
  end

  # --- cmd_list ---

  def test_list_shows_empty_message_when_no_gems_cached
    @cmd.send(:cmd_list)
    assert_match "No skills cached yet", @output.string
  end

  def test_list_shows_gem_names_and_versions
    pre_cache("chunker-ruby", "1.2.3")
    pre_cache("faraday", "2.9.0")
    @cmd.send(:cmd_list)
    assert_match "chunker-ruby", @output.string
    assert_match "1.2.3", @output.string
    assert_match "faraday", @output.string
  end

  def test_list_shows_total_counts
    pre_cache("my_gem", "1.0.0")
    pre_cache("my_gem", "2.0.0")
    @cmd.send(:cmd_list)
    assert_match "1 gem", @output.string
    assert_match "2 version", @output.string
  end

  # --- cmd_purge ---

  def test_purge_raises_without_gem_name
    set_args
    assert_raises(Gem::CommandLineError) { @cmd.send(:cmd_purge) }
  end

  def test_purge_raises_without_version
    set_args("my_gem")
    assert_raises(Gem::CommandLineError) { @cmd.send(:cmd_purge) }
  end

  def test_purge_removes_cached_skill
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem", "1.0.0")
    @cmd.send(:cmd_purge)
    refute GemSkills::Cache.cached?("my_gem", "1.0.0")
    assert_match "Purged", @output.string
  end

  def test_purge_reports_not_cached_via_alert
    set_args("my_gem", "9.9.9")
    @cmd.send(:cmd_purge)
    assert_match "Not cached", @errors.string
  end

  private

  def set_args(*args)
    @cmd.instance_variable_get(:@options)[:args] = args
  end

  def set_option(key, value)
    @cmd.instance_variable_get(:@options)[key] = value
  end

  def pre_cache(gem_name, version)
    dir = File.join(@tmpdir, gem_name, version)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), "# #{gem_name} skill")
  end

  def stub_generator(generated)
    GemSkills::Generator.stub(:new, ->(name, *) {
      obj = Object.new
      obj.define_singleton_method(:generate) { |**| generated << name; "# #{name} skill" }
      obj
    }) { yield }
  end

  def simple_generator
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| "# skill content" }
    obj
  end

  def failing_generator
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| raise GemSkills::Error, "no docs found" }
    obj
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
