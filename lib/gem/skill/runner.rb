# frozen_string_literal: true

module Gem::Skill
  # Core install logic shared by gem_command and bundle_command.
  # Callers are responsible for spinner.auto_spin and title setup before calling.
  module Runner
    # Generate + cache + link one skill.
    # Returns nil on success, error message string on failure.
    def self.install_skill(gem_name, version, spinner, force:, model:)
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
  end
end
