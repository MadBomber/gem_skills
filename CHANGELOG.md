# Changelog

All notable changes to gem-skill are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.1.3] - 2026-06-17

### Added
- `gem skill setup` subcommand — registers gem-skill as a Bundler plugin in one step
- `--version` / `-v` flag for both `gem skill` and `bundle skill`
- `post_install_message` guiding users to run `gem skill setup` after install
- `async` gem dependency — concurrent fiber-based LLM calls replace threads
- `Gem::Skill::Runner` module — shared `install_skill` core extracted from both CLI commands
- `test/support/cache_helpers.rb` — shared `stub_cache_root`/`restore_cache_root` test helpers
- MkDocs documentation site (`docs/`) with full reference for all commands, cache layout, skill file format, and architecture

### Changed
- `bundle skill install` and `bundle skill refresh` now run all gems concurrently via `Async::Barrier` (previously sequential)
- `gem skill install` also migrated from threads to async fibers
- `Lockfile.gems` now includes runtime dependencies declared in gemspec files (via `gemspec` in `Gemfile`), not just direct `Gemfile` entries
- `.claude/skills/` symlinks now point to version directories (e.g. `~/.gem/skills/faraday/2.14.3/`) instead of individual `SKILL.md` files
- `GEMSKILL_DIR` environment variable controls the cache root (default: `~/.gem/skills`)
- `GEMSKILL_MODEL` environment variable controls the default LLM model
- `scripts/e2e_test` updated to exercise the full pipeline: Fetch → Runner → Cache → Linker

### Removed
- `thor` runtime dependency (was declared but never used)

## [0.1.0] - 2026-06-16

- Initial release
