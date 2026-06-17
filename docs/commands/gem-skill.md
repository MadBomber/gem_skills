# gem skill

The `gem skill` command manages the global skill cache at `~/.gem/skills`.
It works with any installed gem regardless of project context.

## Subcommands

### `gem skill install`

Generate and cache a `SKILL.md` for one or more gems.

```bash
gem skill install GEM_NAME [GEM_NAME ...]
```

**Options:**

| Flag | Description |
|------|-------------|
| `--force`, `-f` | Regenerate even if a skill is already cached |
| `--model MODEL`, `-m MODEL` | LLM model to use (overrides `GEMSKILL_MODEL`) |

**Examples:**

```bash
# Single gem (version auto-detected from installed gems)
gem skill install debug_me

# Multiple gems concurrently
gem skill install faraday zeitwerk dry-validation

# Force regeneration with a specific model
gem skill install rails --force --model claude-opus-4-8
```

If a gem is not installed locally, gem-skill will install it automatically
before generating the skill.

All gems are processed concurrently — you'll see a live spinner per gem:

```
⠋ Generating skills (claude-sonnet-4-6)
  ✓ debug_me 1.1.0 done
  ✓ faraday 2.12.0 done
  ⠋ zeitwerk 2.8.2
```

---

### `gem skill setup`

Register gem-skill as a Bundler plugin (run once after `gem install gem-skill`).

```bash
gem skill setup
```

This enables `bundle skill` in any project on the machine. See
[Installation](../installation.md) for details.

---

### `gem skill list`

Show all skills currently in the global cache.

```bash
gem skill list
```

**Example output:**

```
Cached skills in /Users/you/.gem/skills:

  debug_me                       1.1.0
  faraday                        2.12.0, 2.14.3
  zeitwerk                       2.8.2

3 gem(s), 4 version(s) total.
```

---

### `gem skill purge`

Remove a cached skill version.

```bash
# Remove a specific version
gem skill purge GEM_NAME VERSION

# Remove all cached versions of a gem
gem skill purge GEM_NAME --all
```

**Examples:**

```bash
gem skill purge faraday 2.12.0
gem skill purge rails --all
```

---

## `gem install --with-skill`

Generate skills automatically as you install gems:

```bash
gem install faraday zeitwerk --with-skill
```

All gems install normally first. Skills are then generated concurrently after
all installs complete — same spinner UI as `gem skill install`.

This works for any `gem install` command, including version-pinned installs:

```bash
gem install rails --version "~> 7.1" --with-skill
```
