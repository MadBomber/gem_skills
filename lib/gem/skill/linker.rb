# frozen_string_literal: true

require "fileutils"

module Gem::Skill
  # Manages .claude/skills/ symlinks in a project, pointing to ~/.gem/skills cache.
  # Each symlink is a directory link: <gem_name> -> ~/.gem/skills/<gem>/<version>/
  # Claude Code discovers skills by reading SKILL.md inside each linked directory.
  module Linker
    def self.skills_dir(project_root = Dir.pwd)
      File.join(project_root, ".claude", "skills")
    end

    def self.link(gem_name, version, project_root = Dir.pwd)
      target_dir = File.dirname(Cache.skill_path(gem_name, version))
      raise Error, "No cached skill for #{gem_name} #{version}. Run: gem skill install #{gem_name}" \
        unless File.exist?(Cache.skill_path(gem_name, version))

      dir = skills_dir(project_root)
      FileUtils.mkdir_p(dir)

      link_path = File.join(dir, gem_name)
      File.unlink(link_path) if File.symlink?(link_path)
      File.symlink(target_dir, link_path)
    end

    def self.unlink(gem_name, project_root = Dir.pwd)
      link_path = File.join(skills_dir(project_root), gem_name)
      File.unlink(link_path) if File.symlink?(link_path)
    end

    def self.linked_gems(project_root = Dir.pwd)
      dir = skills_dir(project_root)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*")).filter_map do |path|
        next unless File.symlink?(path)

        gem_name   = File.basename(path)
        target_dir = File.readlink(path)
        version    = target_dir.match(%r{/([^/]+)$})&.captures&.first
        skill_file = File.join(target_dir, "SKILL.md")
        { gem_name: gem_name, version: version, target: target_dir, valid: File.exist?(skill_file) }
      end
    end

    def self.prune_dead_links(project_root = Dir.pwd)
      linked_gems(project_root)
        .reject { |entry| entry[:valid] }
        .each   { |entry| unlink(entry[:gem_name], project_root) }
    end
  end
end
