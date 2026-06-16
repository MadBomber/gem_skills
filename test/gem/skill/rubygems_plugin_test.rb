# frozen_string_literal: true

require "test_helper"
require "tmpdir"

require "rubygems/command_manager"
require "rubygems/commands/install_command"
require "rubygems_plugin"

class RubygemsPluginTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
    @errors = StringIO.new
    Gem.ui.instance_variable_set(:@errs, @errors)
    Gem::Skill.pending_skills.clear
  end

  def teardown
    Gem.ui.instance_variable_set(:@errs, STDERR)
    FileUtils.rm_rf(@tmpdir)
    restore_cache_root
    Gem::Skill.pending_skills.clear
  end

  # --- InstallSkillOption ---

  def test_install_command_accepts_with_skill_option
    cmd = Gem::Commands::InstallCommand.new
    assert_silent { cmd.handle_options(%w[my_gem --with-skill]) }
    assert cmd.options[:generate_skill]
  end

  def test_install_command_generate_skill_defaults_to_false
    cmd = Gem::Commands::InstallCommand.new
    cmd.handle_options(%w[my_gem])
    refute cmd.options[:generate_skill]
  end

  # --- post_install hook: collection ---

  def test_post_install_collects_spec_when_flag_set
    call_post_install_hooks(fake_installer("my_gem", "1.0.0", generate_skill: true))
    assert_equal [{ name: "my_gem", version: "1.0.0" }], Gem::Skill.pending_skills
  end

  def test_post_install_skips_when_flag_not_set
    call_post_install_hooks(fake_installer("my_gem", "1.0.0", generate_skill: false))
    assert_empty Gem::Skill.pending_skills
  end

  def test_post_install_collects_multiple_specs
    call_post_install_hooks(fake_installer("gem_a", "1.0.0", generate_skill: true))
    call_post_install_hooks(fake_installer("gem_b", "2.0.0", generate_skill: true))
    assert_equal 2, Gem::Skill.pending_skills.size
    assert_equal "gem_a", Gem::Skill.pending_skills[0][:name]
    assert_equal "gem_b", Gem::Skill.pending_skills[1][:name]
  end

  # --- generate_pending_skills: orchestration ---

  def test_generate_pending_skills_does_nothing_when_empty
    Gem::Skill.pending_skills.clear
    configured = false
    Gem::Skill.stub(:configure_llm!, -> { configured = true }) do
      Gem::Skill.generate_pending_skills
    end
    refute configured
  end

  # --- generate_one_skill: per-gem unit tests (null spinner, no threads) ---

  def test_generate_one_skill_calls_generator_for_gem
    generated = []
    Gem::Skill::Generator.stub(:new, ->(name, _ver) { fake_generator { generated << name } }) do
      Gem::Skill.generate_one_skill("my_gem", "1.0.0", null_spinner)
    end
    assert_includes generated, "my_gem"
  end

  def test_generate_one_skill_does_not_raise_on_gem_skill_error
    Gem::Skill::Generator.stub(:new, ->(*) { failing_generator("no docs found") }) do
      Gem::Skill.generate_one_skill("bad_gem", "1.0.0", null_spinner)  # must not raise
    end
  end

  def test_generate_one_skill_does_not_raise_on_unexpected_error
    Gem::Skill::Generator.stub(:new, ->(*) { failing_generator("network error", RuntimeError) }) do
      Gem::Skill.generate_one_skill("bad_gem", "1.0.0", null_spinner)  # must not raise
    end
  end

  def test_generate_one_skill_calls_success_on_spinner
    sp = null_spinner
    succeeded = false
    sp.define_singleton_method(:success) { |*| succeeded = true }
    Gem::Skill::Generator.stub(:new, ->(*) { fake_generator }) do
      Gem::Skill.generate_one_skill("my_gem", "1.0.0", sp)
    end
    assert succeeded
  end

  def test_generate_one_skill_calls_error_on_spinner_when_failed
    sp = null_spinner
    errored = false
    sp.define_singleton_method(:error) { |*| errored = true }
    Gem::Skill::Generator.stub(:new, ->(*) { failing_generator("bad") }) do
      Gem::Skill.generate_one_skill("bad_gem", "1.0.0", sp)
    end
    assert errored
  end

  private

  def fake_installer(name, version, generate_skill: false)
    spec = Gem::Specification.new { |s| s.name = name; s.version = version }
    inst = Object.new
    inst.define_singleton_method(:options) { { generate_skill: generate_skill } }
    inst.define_singleton_method(:spec)    { spec }
    inst
  end

  def call_post_install_hooks(installer)
    Gem.post_install_hooks.each { |hook| hook.call(installer) }
  end

  def null_spinner
    sp = Object.new
    sp.define_singleton_method(:auto_spin) { }
    sp.define_singleton_method(:update)    { |**| }
    sp.define_singleton_method(:success)   { |*| }
    sp.define_singleton_method(:error)     { |*| }
    sp
  end

  def fake_generator(&on_generate)
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| on_generate&.call; "# skill" }
    obj
  end

  def failing_generator(message, klass = Gem::Skill::Error)
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| raise klass, message }
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
