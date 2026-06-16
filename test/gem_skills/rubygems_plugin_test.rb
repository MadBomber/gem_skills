# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The plugin file is loaded by RubyGems' infrastructure, which guarantees
# CommandManager and the install command are already defined. In tests we must
# pull them in explicitly before loading the plugin.
require "rubygems/command_manager"
require "rubygems/commands/install_command"
require "rubygems_plugin"

class RubygemsPluginTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    stub_cache_root(@tmpdir)
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

  # --- post_install hook ---

  def test_post_install_skips_when_flag_not_set
    installer = fake_installer("my_gem", "1.0.0", generate_skill: false)
    generated = []
    call_post_install_hooks(installer, generated: generated)
    assert_empty generated
  end

  def test_post_install_generates_skill_when_flag_set
    installer = fake_installer("my_gem", "1.0.0", generate_skill: true)
    generated = []
    call_post_install_hooks(installer, generated: generated)
    assert_includes generated, "my_gem"
  end

  def test_post_install_reports_warning_on_gem_skills_error
    installer = fake_installer("my_gem", "1.0.0", generate_skill: true)
    call_post_install_hooks(installer, raise_error: true)
    assert_match "no docs found", @errors.string
  end

  private

  def fake_installer(name, version, generate_skill: false)
    spec = Gem::Specification.new { |s| s.name = name; s.version = version }
    inst = Object.new
    inst.define_singleton_method(:options) { { generate_skill: generate_skill } }
    inst.define_singleton_method(:spec)    { spec }
    inst
  end

  def call_post_install_hooks(installer, generated: [], raise_error: false)
    gen_stub = ->(name, ver, **) {
      obj = Object.new
      obj.define_singleton_method(:generate) do |**|
        raise GemSkills::Error, "no docs found" if raise_error
        generated << name
        "# #{name} skill"
      end
      obj
    }

    GemSkills.stub(:configure_llm!, nil) do
      GemSkills::Generator.stub(:new, gen_stub) do
        Gem.post_install_hooks.each { |hook| hook.call(installer) }
      end
    end
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
