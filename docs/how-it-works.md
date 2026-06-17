# How It Works

gem-skill is built as a pipeline of independent modules. Each has a single
responsibility and can be used or tested in isolation.

## Pipeline overview

```
Gemfile.lock / gem name
      ↓
  Lockfile          parse direct deps + gemspec deps
      ↓
  Fetcher           collect documentation from multiple sources
      ↓
  Generator         call LLM, produce SKILL.md content
      ↓
  Cache             write to ~/.gem/skills/<gem>/<version>/
      ↓
  Linker            symlink .claude/skills/<gem> → cache dir
```

`Runner.install_skill` is the glue that drives steps 2–5 for a single gem.
The CLI commands (`gem skill`, `bundle skill`) fan it out concurrently across
multiple gems using async fibers.

---

## Modules

### Lockfile

`lib/gem/skill/lockfile.rb`

Parses `Gemfile.lock` to produce a `{ gem_name => version }` hash of the gems
to process. Reads from two sections:

- **`DEPENDENCIES`** — direct deps listed in `Gemfile`
- **`PATH` → `specs:`** — runtime deps from any `gemspec` referenced by `gemspec` in `Gemfile`

Versions are resolved from the `GEM → specs:` section, which contains the full
lockfile-resolved version for every gem.

### Fetcher

`lib/gem/skill/fetcher.rb`

Collects documentation from up to three sources, tried in priority order:

1. **Local gem install** — reads `README` and `CHANGELOG` from the gem's install directory via `Gem::Specification`
2. **RubyGems API** — fetches summary, runtime dependencies, source URI
3. **GitHub raw README** — fetched when the gem is not installed locally; tries `main` then `master` branches, and four common README filename variants

Content is truncated at 60,000 characters per source to avoid blowing the LLM
context window.

### Generator

`lib/gem/skill/generator.rb`

Calls the LLM via `ruby_llm`. Constructs a detailed prompt instructing the
model to produce a structured `SKILL.md` covering:

- Overview, Installation, Core API, Common Patterns, Gotchas, Configuration, Testing

Supports both streaming (live output) and non-streaming modes. Strips any
markdown code fence wrapper the model adds despite being told not to.

The model is configurable via `GEMSKILL_MODEL` or `--model`.

### Cache

`lib/gem/skill/cache.rb`

Manages the global skill cache. Structure:

```
~/.gem/skills/               (GEMSKILL_DIR)
└── <gem_name>/
    └── <version>/
        ├── SKILL.md
        └── metadata.json   (gem, version, model, generated_at, sources)
```

`Cache::ROOT` is set once at load time from `GEMSKILL_DIR` (default: `~/.gem/skills`).

### Linker

`lib/gem/skill/linker.rb`

Creates and manages directory symlinks in `.claude/skills/` inside a project:

```
.claude/skills/<gem_name>  →  ~/.gem/skills/<gem_name>/<version>/
```

Symlinks point to the **version directory**, not directly to `SKILL.md`.
Claude Code discovers `SKILL.md` by reading inside the linked directory.

`Linker.prune_dead_links` removes any symlink whose target no longer exists
in the cache (e.g. after `gem skill purge`).

### Runner

`lib/gem/skill/runner.rb`

Shared core used by both CLI commands. Drives one gem through the
cache-check → generate → link sequence:

```ruby
Runner.install_skill(gem_name, version, spinner, force:, model:)
# Returns nil on success, error message string on failure
```

Returns the error message rather than raising, so the caller (the concurrent
fiber) can record it without killing other in-flight fibers.

---

## Concurrency

Both CLI commands use the `async` gem with `Async::Barrier`:

```ruby
Async do
  barrier = Async::Barrier.new
  gems.each do |gem_name, version|
    barrier.async { Runner.install_skill(...) }
  end
  barrier.wait
ensure
  barrier.stop
end
```

Each gem gets its own fiber. Fibers yield to the event loop during network I/O
(HTTP fetches, LLM API calls), so all gems make progress concurrently on a
single thread. This is more memory-efficient than one thread per gem.

---

## Plugin architecture

gem-skill registers itself in two ways:

### RubyGems plugin (`lib/rubygems_plugin.rb`)

Auto-loaded by RubyGems on every `gem` command via the `rubygems_plugin`
naming convention. Prepends `Gem::Skill::InstallSkillOption` onto
`Gem::Commands::InstallCommand` to add the `--with-skill` flag.

After all gem installs complete, `Gem.post_install` collects gem names/versions
into a pending list, and `at_exit` fires `generate_pending_skills` to process
them concurrently.

### Bundler plugin (`plugins.rb`)

Registered via `bundle plugin install gem-skill` (or `gem skill setup`).
Bundler's plugin API loads `plugins.rb` and discovers the
`Gem::Skill::BundlerPlugin` class, which routes `bundle skill SUBCOMMAND` to
`Gem::Skill::BundlerCommand`.
