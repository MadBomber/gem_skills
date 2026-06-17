# frozen_string_literal: true

require_relative "lib/gem/skill/version"

Gem::Specification.new do |spec|
  spec.name = "gem-skill"
  spec.version = Gem::Skill::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Generate and manage Claude Code AI skills from Ruby gem documentation."

  spec.description = <<~DESC
    Automatically generates Claude Code SKILL.md files from a gem's README,
    RubyDoc, and changelog. Skills are cached in ~/.gem/skills and symlinked
    into projects driven by Gemfile.lock. Provides both 'gem skill' and
    'bundle skill' subcommands.
  DESC

  spec.homepage = "https://github.com/madbomber/gem-skill"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  spec.post_install_message = <<~MSG
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      gem-skill installed!

      'gem skill install GEM_NAME' is ready to use.

      To enable 'bundle skill' in your projects, run:

        gem skill setup

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MSG

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async",       "~> 2.0"
  spec.add_dependency "ruby_llm",    "~> 1.0"
  spec.add_dependency "thor",        "~> 1.0"
  spec.add_dependency "tty-spinner"
end
