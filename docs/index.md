# gem-skill

**gem-skill** generates Claude Code skill files from Ruby gem documentation and
caches them globally so every project that uses a gem can share the same
pre-built knowledge.

## The problem it solves

Every time Claude Code encounters a gem it hasn't seen in the current context,
it re-reads the README, scans examples, and figures out the API. That costs
tokens and time — and the result evaporates when the conversation ends.

`gem-skill` runs that pipeline once, offline, and stores the output as a
`SKILL.md` in `~/.gem/skills`. Projects symlink to the cached version, so
Claude has accurate, version-specific knowledge about each gem without
repeating the ingestion work.

## Quick start

```bash
# 1. Install
gem install gem-skill

# 2. Register the Bundler plugin (once per machine)
gem skill setup

# 3. Generate a skill for any installed gem
gem skill install debug_me

# 4. In a project — generate skills for all direct dependencies
cd your-project
bundle skill install
```

## How it works

```
gem README / changelog / RubyGems API
        ↓
   Fetcher collects docs
        ↓
   Generator calls LLM (ruby_llm)
        ↓
   SKILL.md cached at ~/.gem/skills/<gem>/<version>/
        ↓
   Linker creates .claude/skills/<gem> → cache dir
        ↓
   Claude Code reads SKILL.md automatically
```

All concurrent work is handled by async fibers — multiple gems are processed
simultaneously with live TTY spinner progress.

## Key features

- **Global cache** — generate once, use everywhere; skills are version-specific
- **Gemfile.lock awareness** — `bundle skill install` installs skills for every direct dependency including gemspec runtime deps
- **Concurrent** — all LLM calls run concurrently via async fibers
- **Two interfaces** — `gem skill` for global cache management, `bundle skill` for project-aware linking
- **Auto-install** — `gem install --with-skill` generates skills during normal gem installation
- **Configurable** — `GEMSKILL_DIR` and `GEMSKILL_MODEL` environment variables
