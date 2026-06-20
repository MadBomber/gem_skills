# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gem/skill/cli/gem_command"

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
    Gem::Skill.stub(:configure_llm!, nil) { @cmd.execute }
    assert_match "install", @output.string
  end

  def test_execute_shows_usage_and_error_for_unknown_subcommand
    set_args("bogus")
    Gem::Skill.stub(:configure_llm!, nil) { @cmd.execute }
    assert_match "install", @output.string
    assert_match "Unknown subcommand", @errors.string
  end

  # --- cmd_install ---

  def test_install_shows_error_without_gem_name
    set_args
    @cmd.send(:cmd_install)
    assert_match "gem_name required", @errors.string
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
  end

  def test_install_reports_error_when_auto_install_fails
    set_args("no_such_gem_xyz")
    @cmd.stub(:resolve_installed_version, nil) do
      @cmd.stub(:install_gem, ->(*) { raise Gem::Skill::Error, "Could not install 'no_such_gem_xyz'" }) do
        @cmd.send(:cmd_install)
      end
    end
    assert_match "Could not install", @errors.string
  end

  def test_install_skips_generation_when_already_cached
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem")
    generated = []
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_generator(generated) { @cmd.send(:cmd_install) }
    end
    assert_empty generated
  end

  def test_install_generates_and_links_uncached_gem
    set_args("my_gem")
    generated = []
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_generator(generated) { @cmd.send(:cmd_install) }
    end
    assert_includes generated, "my_gem"
  end

  def test_install_multiple_gems
    set_args("gem_a", "gem_b", "gem_c")
    generated = []
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_generator(generated) { @cmd.send(:cmd_install) }
    end
    assert_equal %w[gem_a gem_b gem_c], generated
    assert_match "Tip:", @output.string
  end

  def test_install_continues_after_one_gem_fails
    set_args("bad_gem", "good_gem")
    generated = []
    resolver = ->(name) { "1.0.0" }
    @cmd.stub(:resolve_installed_version, resolver) do
      Gem::Skill::Generator.stub(:new, ->(name, *) {
        name == "bad_gem" ? failing_generator : simple_generator_tracking(generated, name)
      }) { @cmd.send(:cmd_install) }
    end
    assert_match "bad_gem", @errors.string
    assert_includes generated, "good_gem"
  end

  def test_install_force_bypasses_cached_gem
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem")
    set_option(:force, true)
    generated = []
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_generator(generated) { @cmd.send(:cmd_install) }
    end
    assert_includes generated, "my_gem"
  end

  def test_install_passes_custom_model_to_generator
    set_args("my_gem")
    set_option(:model, "claude-haiku-4-5")
    captured = {}
    gen_obj  = simple_generator
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      Gem::Skill::Generator.stub(:new, ->(*_args, **kwargs) { captured.merge!(kwargs); gen_obj }) do
        @cmd.send(:cmd_install)
      end
    end
    assert_equal "claude-haiku-4-5", captured[:model]
  end

  def test_install_rescues_gem_skill_error_and_reports_via_alert
    set_args("my_gem")
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      Gem::Skill::Generator.stub(:new, ->(*) { failing_generator }) do
        @cmd.send(:cmd_install)  # must not raise
      end
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

  def test_list_marks_verified_versions_with_checkmark
    pre_cache("verified_gem", "1.0.0")
    Gem::Skill::Cache.merge_metadata("verified_gem", "1.0.0", verification: { verified: true })
    pre_cache("plain_gem", "2.0.0") # no verification metadata

    @cmd.send(:cmd_list)
    out  = @output.string
    mark = Gem::Commands::SkillCommand::CHECK_MARK

    # The checkmark is ANSI-colored on an interactive terminal, so allow optional
    # SGR codes between the version and the mark.
    verified = /1\.0\.0 (?:\e\[\d+m)*#{Regexp.escape(mark)}/
    assert_match verified, out, "verified version should get a checkmark"
    refute_match "2.0.0 #{mark}", out, "unverified version should have no checkmark"
  end

  def test_skill_verified_predicate
    pre_cache("g", "1.0.0")
    refute @cmd.send(:skill_verified?, "g", "1.0.0")

    Gem::Skill::Cache.merge_metadata("g", "1.0.0", verification: { verified: true })
    assert @cmd.send(:skill_verified?, "g", "1.0.0")
  end

  def test_skill_verified_false_when_verification_skipped
    pre_cache("g", "1.0.0")
    Gem::Skill::Cache.merge_metadata("g", "1.0.0", verification: { verified: false })
    refute @cmd.send(:skill_verified?, "g", "1.0.0")
  end

  def test_format_version_appends_check_only_when_verified
    pre_cache("g", "1.0.0")
    assert_equal "1.0.0", @cmd.send(:format_version, "g", "1.0.0")

    Gem::Skill::Cache.merge_metadata("g", "1.0.0", verification: { verified: true })
    assert_includes @cmd.send(:format_version, "g", "1.0.0"), Gem::Commands::SkillCommand::CHECK_MARK
  end

  # --- cmd_purge ---

  def test_purge_shows_error_without_gem_name
    set_args
    @cmd.send(:cmd_purge)
    assert_match "Usage: gem skill purge", @errors.string
  end

  def test_purge_shows_error_without_version
    set_args("my_gem")
    @cmd.send(:cmd_purge)
    assert_match "Usage: gem skill purge", @errors.string
  end

  def test_purge_all_removes_all_versions_of_gem
    pre_cache("my_gem", "1.0.0")
    pre_cache("my_gem", "2.0.0")
    set_args("my_gem")
    set_option(:all, true)
    @cmd.send(:cmd_purge)
    refute Gem::Skill::Cache.cached?("my_gem", "1.0.0")
    refute Gem::Skill::Cache.cached?("my_gem", "2.0.0")
    assert_match "2 version", @output.string
  end

  def test_purge_all_reports_error_when_no_versions_cached
    set_args("my_gem")
    set_option(:all, true)
    @cmd.send(:cmd_purge)
    assert_match "No cached versions", @errors.string
  end

  def test_purge_removes_cached_skill
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem", "1.0.0")
    @cmd.send(:cmd_purge)
    refute Gem::Skill::Cache.cached?("my_gem", "1.0.0")
    assert_match "Purged", @output.string
  end

  def test_purge_reports_not_cached_via_alert
    set_args("my_gem", "9.9.9")
    @cmd.send(:cmd_purge)
    assert_match "Not cached", @errors.string
  end

  # --- cmd_verify ---

  def test_verify_shows_error_without_gem_name
    set_args
    @cmd.send(:cmd_verify)
    assert_match "gem_name required", @errors.string
  end

  def test_verify_one_errors_when_gem_not_installed
    @cmd.stub(:resolve_installed_version, nil) do
      result = @cmd.send(:verify_one, "ghost_gem", spinner: fake_spinner, model: "m")
      refute result.ok?
      assert_match "not installed", @errors.string
    end
  end

  def test_verify_one_errors_when_skill_not_cached
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      result = @cmd.send(:verify_one, "my_gem", spinner: fake_spinner, model: "m")
      refute result.ok?
      assert_match "no cached skill", @errors.string
    end
  end

  def test_verify_one_does_not_generate
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      # Generation must never happen in the verify path
      Gem::Skill::Generator.stub(:new, ->(*) { raise "should not generate during verify" }) do
        result = @cmd.send(:verify_one, "uncached_gem", spinner: fake_spinner, model: "m")
        refute result.ok?
        assert_match "no cached skill", @errors.string
      end
    end
  end

  def test_verify_one_verifies_cached_skill_in_place
    pre_cache("my_gem", "1.0.0")
    fixed = Gem::Skill::Verifier::Result.new(
      content: "# corrected", changed: true, verifiable: true, model: "m"
    )
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_linker do
        stub_verifier(fixed) do
          result = @cmd.send(:verify_one, "my_gem", spinner: fake_spinner, model: "m")
          assert result.verify_fixed
          assert_equal "# corrected", Gem::Skill::Cache.read("my_gem", "1.0.0")
          assert Gem::Skill::Cache.read_metadata("my_gem", "1.0.0")["verification"]["fixed"]
        end
      end
    end
  end

  def test_cmd_verify_exits_with_fixed_code_when_corrections_applied
    pre_cache("my_gem", "1.0.0")
    set_args("my_gem")
    fixed = Gem::Skill::Verifier::Result.new(
      content: "# corrected", changed: true, verifiable: true, model: "m"
    )
    @cmd.stub(:resolve_installed_version, "1.0.0") do
      stub_linker do
        stub_verifier(fixed) do
          err = assert_raises(Gem::SystemExitException) { @cmd.send(:cmd_verify) }
          assert_equal Gem::Skill::EXIT_VERIFY_FIXED, err.exit_code
        end
      end
    end
  end

  # --- install_router_skill (gem skill setup) ---

  def test_router_skill_template_exists_and_is_valid
    source = File.join(Gem::Skill::ROUTER_SKILL_DIR, "SKILL.md")
    assert File.exist?(source), "bundled router skill should exist at #{source}"
    assert File.read(source).start_with?("---\n"), "router skill should have frontmatter"
  end

  def test_install_router_skill_copies_into_detected_assistant_roots
    Dir.mktmpdir do |home|
      with_env("HOME", home) do
        FileUtils.mkdir_p(File.join(home, ".claude"))
        FileUtils.mkdir_p(File.join(home, ".codex"))

        @cmd.send(:install_router_skill)

        %w[.claude .codex].each do |asst|
          dest = File.join(home, asst, "skills", "ruby-gem-skills", "SKILL.md")
          assert File.exist?(dest), "expected router skill at #{dest}"
        end
        # content matches the bundled template
        src = File.read(File.join(Gem::Skill::ROUTER_SKILL_DIR, "SKILL.md"))
        assert_equal src, File.read(File.join(home, ".claude", "skills", "ruby-gem-skills", "SKILL.md"))
      end
    end
  end

  def test_install_router_skill_skips_undetected_assistants
    Dir.mktmpdir do |home|
      with_env("HOME", home) do
        FileUtils.mkdir_p(File.join(home, ".claude")) # only Claude present

        @cmd.send(:install_router_skill)

        assert File.exist?(File.join(home, ".claude", "skills", "ruby-gem-skills", "SKILL.md"))
        refute Dir.exist?(File.join(home, ".codex")),  "must not create an undetected assistant's home"
        refute Dir.exist?(File.join(home, ".agents")), "must not create an undetected assistant's home"
      end
    end
  end

  def test_install_router_skill_reports_when_none_detected
    Dir.mktmpdir do |home|
      with_env("HOME", home) do
        @cmd.send(:install_router_skill)
        assert_match "No assistant directories detected", @output.string
        refute Dir.exist?(File.join(home, ".claude"))
      end
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    if original.nil?
      ENV.delete(key)
    else
      ENV[key] = original
    end
  end

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
    Gem::Skill::Generator.stub(:new, ->(name, *) {
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

  def simple_generator_tracking(generated, name)
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| generated << name; "# #{name} skill" }
    obj
  end

  def failing_generator
    obj = Object.new
    obj.define_singleton_method(:generate) { |**| raise Gem::Skill::Error, "no docs found" }
    obj
  end

  def fake_spinner
    spinner = Object.new
    %i[auto_spin success error update].each do |m|
      spinner.define_singleton_method(m) { |*| }
    end
    spinner
  end

  def stub_linker
    Gem::Skill::Linker.stub(:link, ->(*) {}) { yield }
  end

  def stub_verifier(result)
    obj = Object.new
    obj.define_singleton_method(:verify) { |_| result }
    Gem::Skill::Verifier.stub(:new, ->(*, **) { obj }) { yield }
  end

end
