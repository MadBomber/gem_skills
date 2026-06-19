# frozen_string_literal: true

require "rubygems/command"
require "async"
require "fileutils"
require "json"
require "tty-spinner"
require "gem/skill"

# Registered as `gem skill` via lib/rubygems_plugin.rb.
# Manages the global ~/.gem/skills cache.
class Gem::Commands::SkillCommand < Gem::Command
  def initialize
    super "skill", "Manage Claude Code AI skills for Ruby gems"

    add_option("-f", "--force",         "Regenerate even if already cached") { |_, o| o[:force] = true }
    add_option("--verify",              "Verify generated skill against gem source and fix mismatches (exit #{Gem::Skill::EXIT_VERIFY_FIXED} if fixes applied)") { |_, o| o[:verify] = true }
    add_option("-a", "--all",           "Purge all cached versions of a gem") { |_, o| o[:all] = true }
    add_option("-m", "--model MODEL",   "LLM model to use (default: #{Gem::Skill::Generator::DEFAULT_MODEL})") do |model, o|
      o[:model] = model
    end
    add_option("-v", "--version",       "Print gem-skill version and exit") { |_, o| o[:version] = true }
  end

  def arguments
    "SUBCOMMAND  one of: install, verify, list, purge, setup"
  end

  def usage
    "#{program_name} install GEM_NAME [GEM_NAME ...]\n" \
    "       #{program_name} verify GEM_NAME [GEM_NAME ...]\n" \
    "       #{program_name} list\n" \
    "       #{program_name} purge GEM_NAME VERSION\n" \
    "       #{program_name} purge GEM_NAME --all\n" \
    "       #{program_name} setup"
  end

  def description
    <<~DESC
      install   Generate and cache a SKILL.md for a gem.
      verify    Verify an already-cached skill against the gem's source and fix
                mismatches (does not generate; errors if not cached).
      list      Show all skills in the global cache (~/.gem/skills).
      purge     Remove a specific cached version.
      setup     Register gem-skill as a Bundler plugin (run once after install).

      Use 'bundle skill install' in any project after running 'gem skill setup'.
    DESC
  end

  def execute
    if options[:version]
      say Gem::Skill::VERSION
      return
    end
    Gem::Skill.configure_llm!
    subcmd = options[:args].shift
    case subcmd
    when "install" then cmd_install
    when "verify"  then cmd_verify
    when "list"    then cmd_list
    when "purge"   then cmd_purge
    when "setup"   then cmd_setup
    when nil
      say usage
    else
      alert_error "Unknown subcommand: #{subcmd.inspect}"
      say usage
    end
  end

  private

  def cmd_install
    gem_names = options[:args].dup
    options[:args].clear

    if gem_names.empty?
      alert_error "gem_name required. Usage: gem skill install GEM_NAME [GEM_NAME ...]"
      return
    end

    force  = options[:force]
    verify = options[:verify]
    model  = options[:model] || Gem::Skill::Generator::DEFAULT_MODEL

    multi = TTY::Spinner::Multi.new(
      "[:spinner] Generating skills (#{model})",
      format: :dots,
      output: $stderr
    )

    results = []
    Async do
      barrier = Async::Barrier.new
      gem_names.each do |gem_name|
        spinner = multi.register("  [:spinner] :title")
        spinner.update(title: gem_name)
        barrier.async { results << install_one(gem_name, spinner: spinner, force: force, model: model, verify: verify) }
      end
      barrier.wait
    ensure
      barrier.stop
    end

    say "Tip: run 'bundle plugin install gem-skill' to enable 'bundle skill'."

    fixed = results.count(&:verify_fixed)
    if verify && fixed.positive?
      say "Verify corrected #{fixed} skill(s) against gem source."
      terminate_interaction Gem::Skill::EXIT_VERIFY_FIXED
    end
  end

  def install_one(gem_name, spinner:, force:, model:, verify: false)
    spinner.auto_spin
    version = resolve_installed_version(gem_name)
    if version.nil?
      spinner.update(title: "#{gem_name} (installing...)")
      version = install_gem(gem_name)
    end
    spinner.update(title: "#{gem_name} #{version}")
    result = Gem::Skill::Runner.install_skill(gem_name, version, spinner, force: force, model: model, verify: verify)
    alert_error "#{gem_name}: #{result.error}" if result.error
    result
  rescue Gem::Skill::Error => e
    spinner.error("failed")
    alert_error "#{gem_name}: #{e.message}"
    Gem::Skill::Runner::Result.failure(e.message)
  end

  def cmd_verify
    gem_names = options[:args].dup
    options[:args].clear

    if gem_names.empty?
      alert_error "gem_name required. Usage: gem skill verify GEM_NAME [GEM_NAME ...]"
      return
    end

    model = options[:model] || Gem::Skill::Generator::DEFAULT_MODEL

    multi = TTY::Spinner::Multi.new(
      "[:spinner] Verifying skills (#{model})",
      format: :dots,
      output: $stderr
    )

    results = []
    Async do
      barrier = Async::Barrier.new
      gem_names.each do |gem_name|
        spinner = multi.register("  [:spinner] :title")
        spinner.update(title: gem_name)
        barrier.async { results << verify_one(gem_name, spinner: spinner, model: model) }
      end
      barrier.wait
    ensure
      barrier.stop
    end

    fixed = results.count(&:verify_fixed)
    if fixed.positive?
      say "Verify corrected #{fixed} skill(s) against gem source."
      terminate_interaction Gem::Skill::EXIT_VERIFY_FIXED
    end
  end

  # Verify an already-cached skill in place. Never generates: the gem must be
  # installed (verification needs its source) and the skill must already be cached.
  def verify_one(gem_name, spinner:, model:)
    spinner.auto_spin
    version = resolve_installed_version(gem_name)
    if version.nil?
      spinner.error("not installed")
      alert_error "#{gem_name}: not installed locally; verification needs the gem's source. Run 'gem install #{gem_name}' first."
      return Gem::Skill::Runner::Result.failure("not installed")
    end

    spinner.update(title: "#{gem_name} #{version}")
    unless Gem::Skill::Cache.cached?(gem_name, version)
      spinner.error("not cached")
      alert_error "#{gem_name} #{version}: no cached skill to verify. Run 'gem skill install #{gem_name}' first."
      return Gem::Skill::Runner::Result.failure("not cached")
    end

    result = Gem::Skill::Runner.install_skill(gem_name, version, spinner, force: false, model: model, verify: true)
    alert_error "#{gem_name}: #{result.error}" if result.error
    result
  rescue Gem::Skill::Error => e
    spinner.error("failed")
    alert_error "#{gem_name}: #{e.message}"
    Gem::Skill::Runner::Result.failure(e.message)
  end

  def cmd_list
    gems = Gem::Skill::Cache.all_gems
    if gems.empty?
      say "No skills cached yet."
      say "Run: gem skill install GEM_NAME"
      return
    end

    say "Cached skills in #{Gem::Skill::Cache.root}:"
    say ""
    gems.each do |name|
      versions = Gem::Skill::Cache.versions(name)
      rendered = versions.map { |v| format_version(name, v) }.join(", ")
      say "  %-30s %s" % [name, rendered]
    end
    say ""
    say "#{gems.size} gem(s), #{gems.sum { |n| Gem::Skill::Cache.versions(n).size }} version(s) total."
  end

  CHECK_MARK = "✓" # ✓

  # True when the cached skill for this gem/version was verified against source.
  def skill_verified?(gem_name, version)
    Gem::Skill::Cache.read_metadata(gem_name, version).dig("verification", "verified") == true
  end

  # A version label, with a green checkmark appended when the skill is verified.
  def format_version(gem_name, version)
    return version unless skill_verified?(gem_name, version)

    "#{version} #{colorize_check}"
  end

  # The checkmark, ANSI-green only when writing to an interactive terminal so
  # redirected/piped output stays clean.
  def colorize_check
    $stdout.tty? ? "\e[32m#{CHECK_MARK}\e[0m" : CHECK_MARK
  end

  def cmd_setup
    plugin_list = `bundle plugin list 2>/dev/null`
    if plugin_list.include?("gem-skill")
      say "gem-skill is already registered as a Bundler plugin."
      say "Use 'bundle skill install' in any project."
      return
    end

    say "Registering gem-skill as a Bundler plugin..."
    if system("bundle", "plugin", "install", "gem-skill")
      say "Done. Use 'bundle skill install' in any project."
    else
      alert_error "Failed. Try running manually: bundle plugin install gem-skill"
    end
  end

  def cmd_purge
    gem_name = options[:args].shift
    unless gem_name
      alert_error "Usage: gem skill purge GEM_NAME VERSION\n       gem skill purge GEM_NAME --all"
      return
    end

    if options[:all]
      versions = Gem::Skill::Cache.versions(gem_name)
      if versions.empty?
        alert_error "No cached versions for '#{gem_name}'"
        return
      end
      versions.each { |v| Gem::Skill::Cache.purge(gem_name, v) }
      say "Purged #{versions.size} version(s) of #{gem_name}"
      return
    end

    version = options[:args].shift
    unless version
      alert_error "Usage: gem skill purge GEM_NAME VERSION\n       gem skill purge GEM_NAME --all"
      return
    end

    unless Gem::Skill::Cache.cached?(gem_name, version)
      alert_error "Not cached: #{gem_name} #{version}"
      return
    end

    Gem::Skill::Cache.purge(gem_name, version)
    say "Purged: #{gem_name} #{version}"
  end

  def resolve_installed_version(gem_name)
    Gem::Specification.find_by_name(gem_name)&.version&.to_s
  rescue Gem::MissingSpecError
    nil
  end

  def install_gem(gem_name, version = nil)
    req   = version ? Gem::Requirement.new("= #{version}") : Gem::Requirement.default
    specs = Gem.install(gem_name, req)
    specs.find { |s| s.name == gem_name }&.version&.to_s
  rescue Gem::InstallError, Gem::GemNotFoundException, StandardError => e
    raise Gem::Skill::Error, "Could not install '#{gem_name}': #{e.message}"
  end
end
