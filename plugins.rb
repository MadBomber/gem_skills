# frozen_string_literal: true

# Bundler plugin entry point — loaded by `bundle plugin install gem_skills`
# or `plugin 'gem_skills'` in Gemfile. Registers the `bundle skill` command.

require_relative "lib/gem_skills/cli/bundle_command"

Bundler::Plugin::API.commands "skill" do |_command, args|
  GemSkills::BundlerCommand.run(args)
end
