# gem-skill

<p align="center">
<table style="width:38%;margin:0 auto;" border="0" cellpadding="8">
  <tr>
    <td width="40%"><img src="docs/assets/images/gem-skill.jpg" alt="gem-skill logo" width="100%"></td>
    <td width="60%">
      Generate <code>SKILL.md</code> files for AI coding assistants
      (Claude Code, OpenAI Codex, and others) from Ruby gem documentation,
      and cache them globally so every project that uses a gem can share the
      same pre-built knowledge.<br><br>
      <strong><a href="https://madbomber.github.io/gem-skill">Full documentation →</a></strong>
    </td>
  </tr>
</table>
</p>

## The problem it solves

Every time an AI coding assistant encounters a gem it hasn't seen in the current
context, it re-reads the README, scans examples, and figures out the API. That
costs tokens and time — and the result evaporates when the conversation ends.

`gem-skill` runs that pipeline once, offline, and stores the output as a
`SKILL.md` in `~/.gem/skills`. Projects symlink to the cached version, so your
assistant has accurate, version-specific knowledge about each gem without
repeating the ingestion work. `SKILL.md` is a shared format — Claude Code,
OpenAI Codex, and other assistants all read it.

## How the cache is laid out

```
~/.gem/skills/
└── chunker-ruby/
    ├── 1.2.3/
    │   ├── SKILL.md        ← generated skill
    │   └── metadata.json   ← gem name, version, model used, generated_at
    └── 1.4.0/
        ├── SKILL.md
        └── metadata.json
```

Each project's `.claude/skills/` directory (Claude Code's convention) holds
symlinks that point into this cache:

```
your-app/.claude/skills/
└── chunker-ruby/  →  ~/.gem/skills/chunker-ruby/1.2.3/
```

Two projects that pin different versions of the same gem each get the right
skill; the underlying content is generated once and shared.

### Using the cache with other assistants

The `~/.gem/skills` cache is assistant-neutral — `SKILL.md` is a shared format.
By default `bundle skill` links skills into `.claude/skills/`, which Claude Code
reads automatically. Other assistants discover skills in their own roots; for
example, OpenAI Codex looks in `~/.codex/skills` and the vendor-neutral
`~/.agents/skills` (and project-local `.agents/` / `.codex/`).

To make `bundle skill` link into a different project directory, set
`GEMSKILL_PROJECT_DIR`:

```bash
export GEMSKILL_PROJECT_DIR=".agents"   # Codex project root
bundle skill install                    # symlinks now land in .agents/
```

> **Availability ≠ activation.** Claude Code treats every `SKILL.md` under
> `.claude/skills/` as active automatically. Some assistants (e.g. Codex) only
> activate a skill if it's in the session's available-skills list or you point
> at it explicitly — so linking makes a skill *available*, not necessarily
> *active*. See
> [Using with other assistants](https://madbomber.github.io/gem-skill/skill-files/#using-with-other-assistants).

## Installation

```bash
gem install gem-skill
gem skill setup
```

`gem install` gives you the `gem skill` subcommand.
`gem skill setup` registers gem-skill as a Bundler plugin, enabling `bundle skill` in any project.

You only need to run `gem skill setup` once per machine. Alternatively, you can
add the plugin directly to a project's `Gemfile`:

```ruby
plugin "gem-skill"
```

## Requirements

`gem-skill` uses [RubyLLM](https://github.com/crmne/ruby_llm) to generate
skills. Configure at least one provider API key before running:

```bash
export OPENAI_API_KEY="..."      # default model: gpt-5.5
export ANTHROPIC_API_KEY="..."   # or use Claude
export GEMINI_API_KEY="..."      # or Gemini
```

## Configuration

Two environment variables control `gem-skill`'s behaviour:

| Variable | Default | Description |
|---|---|---|
| `GEMSKILL_DIR` | `~/.gem/skills` | Root directory for the global skill cache |
| `GEMSKILL_PROJECT_DIR` | `.claude/skills` | Project-relative directory where `bundle skill` writes symlinks |
| `GEMSKILL_MODEL` | `gpt-5.5` | LLM model used when generating skills |

```bash
# Store skills on a shared drive accessible to all projects
export GEMSKILL_DIR="/Volumes/shared/gem-skills"

# Switch the default model to Claude
export GEMSKILL_MODEL="claude-sonnet-4-6"

# Codex users: link skills into a Codex project root instead of .claude/skills
export GEMSKILL_PROJECT_DIR=".agents"   # or ".codex"
```

The `--model` flag on any command overrides `GEMSKILL_MODEL` for that
invocation. `GEMSKILL_DIR` applies everywhere the cache is read or written.

## Usage

### `gem skill` — global cache management

```bash
# Generate a skill for an installed gem (version auto-detected)
gem skill install chunker-ruby

# Install skills for multiple gems at once (runs concurrently)
gem skill install chunker-ruby faraday debug_me

# Force regeneration even if already cached
gem skill install chunker-ruby --force

# Use a different model
gem skill install chunker-ruby --model claude-haiku-4-5

# Verify an already-cached skill against the gem's source (fixes mismatches)
gem skill verify chunker-ruby

# Show everything in the cache (verified versions are flagged with a ✓)
gem skill list

# Remove a specific cached version
gem skill purge chunker-ruby 1.2.3

# Remove all cached versions of a gem
gem skill purge chunker-ruby --all

# Print the installed version
gem skill --version
```

If a gem isn't installed locally, `gem skill install` will install it first.

### `gem skill setup`

Run once after `gem install gem-skill` to enable `bundle skill` globally:

```bash
gem skill setup
```

This registers gem-skill as a Bundler plugin so `bundle skill` works in every project.

### `gem install --with-skill`

Generate skills for gems as you install them:

```bash
gem install faraday debug_me --with-skill
```

Skills are generated concurrently after all gems finish installing.

### `bundle skill` — project-aware, driven by Gemfile.lock

Run from your project root after `bundle install`:

```bash
# Generate and link skills for all direct dependencies
bundle skill install

# Re-sync after bundle update (skips gems already at the correct version)
bundle skill refresh

# Show what's linked in this project
bundle skill list

# Options available on install and refresh
bundle skill install --force
bundle skill install --model claude-haiku-4-5

# Print the installed version
bundle skill --version
```

## What gets generated

Each `SKILL.md` covers:

- **Overview** — what the gem does and when to use it
- **Installation** — exact Gemfile lines and post-install steps
- **Core API** — key classes and methods with real code examples
- **Common Patterns** — the 3–5 most frequent real-world usage patterns
- **Gotchas & Edge Cases** — surprising defaults, version-specific behavior,
  thread safety, encoding issues
- **Configuration** — initializer patterns and environment variables
- **Testing** — how to test code that uses the gem

The content is synthesized from three sources, tried in priority order:

1. Local gem install (`Gem::Specification` → `gem_dir`) — README and CHANGELOG
2. RubyGems API — summary, runtime dependencies, source URI
3. GitHub raw README — fetched when the gem isn't installed locally

## Development

```bash
git clone https://github.com/madbomber/gem-skill
cd gem-skill
bundle install
bundle exec rake test
```

## Contributing

Bug reports and pull requests welcome at https://github.com/madbomber/gem-skill.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
