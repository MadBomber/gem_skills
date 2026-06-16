# frozen_string_literal: true

require "fileutils"

module Gem::Skill
  # Manages .claude/skills/ symlinks in a project, pointing to ~/.gem/skills cache.
  module Linker
    def self.skills_dir(project_root = Dir.pwd)
      File.join(project_root, ".claude", "skills")
    end

    def self.link(gem_name, version, project_root = Dir.pwd)
      target = Cache.skill_path(gem_name, version)
      raise Error, "No cached skill for #{gem_name} #{version}. Run: gem skill install #{gem_name}" \
        unless File.exist?(target)

      dir = skills_dir(project_root)
      FileUtils.mkdir_p(dir)

      link_path = File.join(dir, "#{gem_name}.md")
      File.unlink(link_path) if File.symlink?(link_path)
      File.symlink(target, link_path)
    end

    def self.unlink(gem_name, project_root = Dir.pwd)
      link_path = File.join(skills_dir(project_root), "#{gem_name}.md")
      File.unlink(link_path) if File.symlink?(link_path)
    end

    def self.linked_gems(project_root = Dir.pwd)
      dir = skills_dir(project_root)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.md")).filter_map do |path|
        next unless File.symlink?(path)

        gem_name = File.basename(path, ".md")
        target   = File.readlink(path)
        version  = target.match(%r{/([^/]+)/SKILL\.md$})&.captures&.first
        { gem_name: gem_name, version: version, target: target, valid: File.exist?(target) }
      end
    end

    def self.prune_dead_links(project_root = Dir.pwd)
      linked_gems(project_root)
        .reject { |entry| entry[:valid] }
        .each   { |entry| unlink(entry[:gem_name], project_root) }
    end
  end
end
