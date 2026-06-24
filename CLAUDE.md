# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem does

`gem-skill` generates `SKILL.md` files from Ruby gem documentation using an LLM, caches them globally at `~/.gem/skills/<gem_name>/<version>/SKILL.md`, and symlinks them into projects at `.claude/skills/<gem_name>.md`. It registers two CLI entry points: `gem skill` (global cache management) and `bundle skill` (project-aware, driven by `Gemfile.lock`).

## Commands

```bash
bundle install
bundle exec rake test                    # run all tests (default task)
ruby -Ilib:test test/gem/skill/cache_test.rb   # run a single test file
bundle exec ruby bin/e2e_test [GEM VERSION MODEL]  # live LLM end-to-end test
```

## Architecture

### Entry points

- `lib/rubygems_plugin.rb` — loaded automatically by RubyGems; registers `gem skill` via `Gem::Commands::SkillCommand`
- `plugins.rb` — Bundler plugin entry point; registers `bundle skill` via `Gem::Skill::BundlerCommand`

### Core pipeline (in call order)

1. **`Lockfile`** (`lib/gem/skill/lockfile.rb`) — parses `Gemfile.lock`; extracts direct-dependency name→version pairs by cross-referencing the `DEPENDENCIES` and `specs:` sections
2. **`Fetcher`** (`lib/gem/skill/fetcher.rb`) — collects raw docs for a single gem/version in priority order: (1) local `Gem::Specification` gem_dir, (2) RubyGems API JSON, (3) GitHub raw README. Returns `{metadata:, readme:, changelog:}` with only populated keys
3. **`Generator`** (`lib/gem/skill/generator.rb`) — formats fetched sources into a prompt, calls RubyLLM (default: `claude-sonnet-4-6`), strips any wrapping code fence, stores result via `Cache`. Supports streaming via block
4. **`Cache`** (`lib/gem/skill/cache.rb`) — reads/writes `~/.gem/skills/<name>/<version>/SKILL.md` and `metadata.json`
5. **`Linker`** (`lib/gem/skill/linker.rb`) — creates/updates symlinks in `.claude/skills/` pointing into the cache; `prune_dead_links` removes broken symlinks after a refresh

### CLI layer

- `lib/gem/skill/cli/gem_command.rb` — `Gem::Commands::SkillCommand`; subcommands: `install`, `list`, `purge`
- `lib/gem/skill/cli/bundle_command.rb` — `Gem::Skill::BundlerCommand`; subcommands: `install`, `refresh`, `list`. `install` = generate + link all lockfile gems; `refresh` = skip already-linked gems at the correct version

### LLM configuration

`Gem::Skill.configure_llm!` reads from environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc.) and configures RubyLLM. Called automatically by both CLI entry points. No-op if already configured.

## Key constants

- `Cache::ROOT` = `~/.gem/skills`
- `Generator::DEFAULT_MODEL` = `"claude-sonnet-4-6"`
- `Generator::MAX_TOKENS` = 32,767 (override via `GEMSKIL_MAX_TOKENS` env var)
- `Generator::DEFAULT_TEMPERATURE` = 0.2 (override via `GEMSKILL_TEMPERATURE` env var; skipped for models that reject temperature)
- `Generator::MAX_SOURCE_CHARS` = 60,000 (README truncation guard)
- Symlink location per project: `.claude/skills/<gem_name>.md → ~/.gem/skills/<gem_name>/<version>/SKILL.md`

## Testing

Uses Minitest. Unit tests live in `test/gem/skill/`. The `bin/e2e_test` script runs a full live pipeline (fetch → generate → cache) against a real LLM and requires at least one provider API key.
