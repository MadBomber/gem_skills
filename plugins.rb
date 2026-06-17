# frozen_string_literal: true

# Bundler plugin entry point — loaded by `bundle plugin install gem-skill`
# or `plugin 'gem-skill'` in Gemfile. Registers the `bundle skill` command.

require_relative "lib/gem/skill/cli/bundle_command"

# Bundler invokes `@commands[command].new.exec(command, args)`, so the command
# is a Bundler::Plugin::API subclass that declares the command and implements exec.
class Gem::Skill::BundlerPlugin < Bundler::Plugin::API
  command "skill"

  def exec(_command, args)
    Gem::Skill::BundlerCommand.run(args)
  end
end
