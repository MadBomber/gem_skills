# frozen_string_literal: true

require "fileutils"
require "json"
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

      force = opts[:force]
      model = opts[:model] || Generator::DEFAULT_MODEL
      errors = []

      puts "Installing skills for #{gems.size} gem(s) (model: #{model})..."
      puts ""

      gems.each do |gem_name, version|
        if Cache.cached?(gem_name, version) && !force
          print "  skip  #{gem_name} #{version}"
        else
          print "  gen   #{gem_name} #{version}  "
          $stdout.flush
          Generator.new(gem_name, version, model: model).generate(force: force) do |chunk|
            print chunk
            $stdout.flush
          end
        end

        Linker.link(gem_name, version)
        puts "  ✓"
      rescue Gem::Skill::Error => e
        puts "  ✗ #{e.message}"
        errors << "#{gem_name} #{version}: #{e.message}"
      end

      Linker.prune_dead_links

      puts ""
      puts "Done. #{gems.size - errors.size}/#{gems.size} skill(s) linked into .claude/skills/"

      if errors.any?
        puts ""
        puts "Errors:"
        errors.each { |e| puts "  #{e}" }
      end
    end

    def self.refresh(opts = {})
      gems   = Lockfile.gems
      linked = Linker.linked_gems.to_h { |e| [e[:gem_name], e[:version]] }
      force  = opts[:force]
      model  = opts[:model] || Generator::DEFAULT_MODEL
      errors = []

      puts "Refreshing skills (model: #{model})..."
      puts ""

      gems.each do |gem_name, version|
        if !force && linked[gem_name] == version
          puts "  ok    #{gem_name} #{version}"
          next
        end

        action = linked.key?(gem_name) ? "update" : "new"
        print "  #{action.ljust(6)}#{gem_name} #{version}  "
        $stdout.flush

        Generator.new(gem_name, version, model: model).generate(force: force) do |chunk|
          print chunk
          $stdout.flush
        end

        Linker.link(gem_name, version)
        puts "  ✓"
      rescue Gem::Skill::Error => e
        puts "  ✗ #{e.message}"
        errors << "#{gem_name} #{version}: #{e.message}"
      end

      Linker.prune_dead_links

      puts ""
      puts "Refreshed."
      if errors.any?
        puts ""
        puts "Errors:"
        errors.each { |e| puts "  #{e}" }
      end
    end

    def self.list
      entries = Linker.linked_gems
      if entries.empty?
        puts "No skills linked in this project."
        puts "Run: bundle skill install"
        return
      end

      ok      = entries.count { |e| e[:valid] }
      broken  = entries.size - ok

      puts "Skills linked in .claude/skills/  (#{ok} ok#{broken > 0 ? ", #{broken} broken" : ""}):"
      puts ""
      entries.each do |e|
        status = e[:valid] ? "ok    " : "BROKEN"
        puts "  [#{status}]  %-30s %s" % [e[:gem_name], e[:version]]
      end
    end

    # --- private ---

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
