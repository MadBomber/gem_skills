# frozen_string_literal: true

require_relative "gem/skill/cli/gem_command"
Gem::CommandManager.instance.register_command :skill

require "rubygems/commands/install_command"
require "tty-spinner"

module Gem::Skill
  module InstallSkillOption
    def initialize
      super
      add_option("--with-skill", "Generate Claude Code SKILL.md files after installation") do |_, opts|
        opts[:generate_skill] = true
      end
    end
  end
end

Gem::Commands::InstallCommand.prepend(Gem::Skill::InstallSkillOption)

module Gem::Skill
  @pending_skills = []
  @pending_lock   = Mutex.new

  class << self
    attr_reader :pending_skills, :pending_lock

    def generate_pending_skills
      return if @pending_skills.empty?

      configure_llm!

      multi = TTY::Spinner::Multi.new(
        "[:spinner] Writing skills",
        format: :dots,
        output: $stderr
      )

      threads = @pending_skills.map do |gem_info|
        name    = gem_info[:name]
        version = gem_info[:version]
        sp = multi.register("  [:spinner] :title")
        sp.update(title: "#{name} #{version}")
        Thread.new(name, version, sp) { |n, v, spinner| generate_one_skill(n, v, spinner) }
      end
      threads.each(&:join)
    rescue => e
      warn "gem-skill: #{e.message}"
    end

    def generate_one_skill(name, version, spinner)
      spinner.auto_spin
      Generator.new(name, version).generate
      spinner.success("done")
    rescue => e
      spinner.error("failed")
      warn "gem-skill: #{name}: #{e.message}"
    end
  end
end

Gem.post_install do |installer|
  next unless installer.options[:generate_skill]
  Gem::Skill.pending_lock.synchronize do
    Gem::Skill.pending_skills << { name: installer.spec.name, version: installer.spec.version.to_s }
  end
end

at_exit { Gem::Skill.generate_pending_skills }
