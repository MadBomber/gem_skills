# frozen_string_literal: true

module Gem::Skill
  # Builds the YAML frontmatter that makes a SKILL.md discoverable as an Agent
  # Skill. Both Claude Code and OpenAI Codex require `name` + `description`
  # frontmatter; without it the file is never registered/triggered as a skill.
  #
  # Constraints satisfied here (intersection of both assistants):
  #   - name: lowercase letters, digits, hyphens only; no leading/trailing or
  #     doubled hyphens; <= 40 chars (Claude Code's rule, also valid for Codex)
  #   - description: single line, no angle brackets (Claude Code rejects < and >),
  #     length-capped (Codex shortens long descriptions)
  #
  # Generation is deterministic (no LLM): the name is derived from the gem name
  # and the description from the skill's Overview section, so the frontmatter is
  # always valid regardless of what the model emitted.
  module Frontmatter
    MAX_NAME_LENGTH        = 40
    MAX_DESCRIPTION_LENGTH = 500

    module_function

    # Return content with a freshly-built, valid frontmatter block. Any existing
    # leading frontmatter is stripped and replaced, so this is idempotent.
    def build(gem_name, version, content)
      body = strip(content)
      fm   = "---\nname: #{slug(gem_name)}\ndescription: #{yaml_quote(description_for(gem_name, version, body))}\n---\n"
      "#{fm}\n#{body}"
    end

    # True when content already begins with a YAML frontmatter block.
    def present?(content)
      content.to_s.lstrip.start_with?("---")
    end

    # Remove a leading frontmatter block (if any) and return the body.
    def strip(content)
      content.to_s.sub(/\A\s*---\s*\n.*?\n---\s*\n+/m, "").lstrip
    end

    # Gem name -> valid skill name. "ruby_llm" -> "ruby-llm", "TTY-Spinner" ->
    # "tty-spinner". Falls back to "skill" if nothing usable remains.
    def slug(gem_name)
      s = gem_name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      s = "skill" if s.empty?
      s[0, MAX_NAME_LENGTH].sub(/-+\z/, "")
    end

    # Derive a trigger-oriented description from the body's Overview section,
    # appending the version for context. Sanitized for both assistants.
    def description_for(gem_name, version, body)
      overview = body[/^##\s+Overview\s*\n+(.+?)(?=\n\s*\n|\n##\s|\z)/m, 1]
      text     = overview || "Ruby gem #{gem_name}. Use when working with #{gem_name} in Ruby code."
      text     = text.gsub(/\s+/, " ").delete("<>").strip
      text     = "#{text} (#{gem_name} v#{version})" unless text.include?(version.to_s)
      text[0, MAX_DESCRIPTION_LENGTH].strip
    end

    # Quote a string as a YAML double-quoted scalar, escaping \ and ".
    def yaml_quote(str)
      %("#{str.gsub(/[\\"]/) { |c| "\\#{c}" }}")
    end
  end
end
