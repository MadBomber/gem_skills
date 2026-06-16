# frozen_string_literal: true

# Bundler plugin entry point — loaded by `bundle plugin install gem-skill`
# or `plugin 'gem-skill'` in Gemfile. Registers the `bundle skill` command.

require_relative "lib/gem/skill/cli/bundle_command"

Bundler::Plugin::API.commands "skill" do |_command, args|
  Gem::Skill::BundlerCommand.run(args)
end
