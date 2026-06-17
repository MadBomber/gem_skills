# frozen_string_literal: true

require "fileutils"
require "json"
require "tty-spinner"
require "gem/skill"

module Gem::Skill
  # Handles `bundle skill SUBCOMMAND` via Bundler's plugin API (plugins.rb).
  # Project-aware: reads Gemfile.lock and manages .claude/skills/ symlinks.
  module BundlerCommand
    SUBCOMMANDS = %w[install refresh list].freeze

    def self.run(args)
      Gem::Skill.configure_llm!
      opts, rest = parse_options(args)
      subcmd = rest.shift

      case subcmd
      when "install" then install(opts)
      when "refresh" then refresh(opts)
      when "list"    then list
      when nil, "help", "--help"
        puts usage
      else
        warn "gem-skill: unknown subcommand #{subcmd.inspect}"
        warn usage
        exit 1
      end
    end

    def self.install(opts = {})
      gems = Lockfile.gems
      if gems.empty?
        puts "No gems found in Gemfile.lock."
        return
      end

      force        = opts[:force]
      model        = opts[:model] || Generator::DEFAULT_MODEL
      errors       = []
      errors_lock  = Mutex.new

      multi = TTY::Spinner::Multi.new(
        "[:spinner] Installing skills (#{model})",
        format: :dots,
        output: $stderr
      )

      threads = gems.map do |gem_name, version|
        sp = multi.register("  [:spinner] :title")
        sp.update(title: "#{gem_name} #{version}")
        Thread.new(gem_name, version, sp) do |name, ver, spinner|
          err = install_one(name, ver, spinner, force: force, model: model)
          errors_lock.synchronize { errors << "#{name} #{ver}: #{err}" } if err
        end
      end

      threads.each(&:join)
      Linker.prune_dead_links

      if errors.any?
        warn ""
        warn "Errors (#{errors.size}):"
        errors.each { |e| warn "  #{e}" }
      end
    end

    def self.refresh(opts = {})
      gems         = Lockfile.gems
      linked       = Linker.linked_gems.to_h { |e| [e[:gem_name], e[:version]] }
      force        = opts[:force]
      model        = opts[:model] || Generator::DEFAULT_MODEL
      errors       = []
      errors_lock  = Mutex.new

      multi = TTY::Spinner::Multi.new(
        "[:spinner] Refreshing skills (#{model})",
        format: :dots,
        output: $stderr
      )

      threads = gems.map do |gem_name, version|
        sp = multi.register("  [:spinner] :title")
        sp.update(title: "#{gem_name} #{version}")
        Thread.new(gem_name, version, sp) do |name, ver, spinner|
          err = if !force && linked[name] == ver
            spinner.auto_spin
            spinner.success("up to date")
            nil
          else
            install_one(name, ver, spinner, force: force, model: model)
          end
          errors_lock.synchronize { errors << "#{name} #{ver}: #{err}" } if err
        end
      end

      threads.each(&:join)
      Linker.prune_dead_links

      if errors.any?
        warn ""
        warn "Errors (#{errors.size}):"
        errors.each { |e| warn "  #{e}" }
      end
    end

    def self.list
      entries = Linker.linked_gems
      if entries.empty?
        puts "No skills linked in this project."
        puts "Run: bundle skill install"
        return
      end

      ok     = entries.count { |e| e[:valid] }
      broken = entries.size - ok

      puts "Skills linked in .claude/skills/  (#{ok} ok#{broken > 0 ? ", #{broken} broken" : ""}):"
      puts ""
      entries.each do |e|
        status = e[:valid] ? "ok    " : "BROKEN"
        puts "  [#{status}]  %-30s %s" % [e[:gem_name], e[:version]]
      end
    end

    # --- private ---

    def self.install_one(gem_name, version, spinner, force:, model:)
      spinner.auto_spin
      if Cache.cached?(gem_name, version) && !force
        Linker.link(gem_name, version)
        spinner.success("already cached")
        return nil
      end
      Generator.new(gem_name, version, model: model).generate(force: force)
      Linker.link(gem_name, version)
      spinner.success("done")
      nil
    rescue => e
      spinner.error("failed")
      e.message
    end
    private_class_method :install_one

    def self.parse_options(args)
      opts      = {}
      remaining = []

      args.each do |arg|
        case arg
        when "--force"           then opts[:force] = true
        when /\A--model(?:=(.+))?\z/
          opts[:model] = $1 || args[args.index(arg) + 1]
        else
          remaining << arg unless opts[:model].nil? && arg !~ /\A--/
          remaining << arg if arg !~ /\A--/
        end
      end

      [opts, remaining]
    end
    private_class_method :parse_options

    def self.usage
      <<~USAGE
        Usage: bundle skill SUBCOMMAND [OPTIONS]

        Subcommands:
          install   Generate and link skills for all gems in Gemfile.lock
          refresh   Re-sync .claude/skills/ after bundle update
          list      Show skills linked in this project

        Options:
          --force         Regenerate even if already cached
          --model MODEL   LLM model to use (default: #{Generator::DEFAULT_MODEL})
      USAGE
    end
    private_class_method :usage
  end
end
