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
| `--verify` | After generating, verify the skill's code against the gem's actual source and fix mismatches |
| `--model MODEL`, `-m MODEL` | LLM model to use (overrides `GEMSKILL_MODEL`) |
| `--version`, `-v` | Print the installed gem-skill version and exit |

**Examples:**

```bash
# Single gem (version auto-detected from installed gems)
gem skill install debug_me

# Multiple gems concurrently
gem skill install faraday zeitwerk dry-validation

# Force regeneration with a specific model
gem skill install rails --force --model claude-opus-4-8

# Generate, then verify the result against the gem's source code
gem skill install tty-spinner --verify
```

If a gem is not installed locally, gem-skill will install it automatically
before generating the skill.

### Verifying against source (`--verify`)

The generation pass synthesizes a skill from a gem's README, changelog, and
examples. That prose is sometimes stale or wrong about exact method signatures,
default argument values, and behavior. `--verify` adds a second pass that checks
the generated skill against the gem's **actual installed source code** (the only
source of truth) and rewrites anything the source contradicts.

Verification requires the gem to be installed locally (it reads `lib/**/*.rb`).
If no source is available, the skill is left untouched.

**Exit status** (so CI can detect README/source drift):

| Code | Meaning |
|------|---------|
| `0` | Success — skill was clean, or `--verify` not used |
| `1` | Error |
| `2` | `--verify` found and corrected problems |

Either way, `metadata.json` gains a `verification` block recording that the gem's
actual source was consulted, which files were examined, and — when fixes were
applied — an array of structured, issue-ready corrections (affected symbol,
source location, what the skill said vs. the truth, and the proving source
snippet). See [Cache layout](cache.md#metadatajson) for the full schema.

A verified skill is flagged with a green checkmark in
[`gem skill list`](#gem-skill-list).

---

### `gem skill verify`

Verify an **already-cached** skill against the gem's source, in place, without
regenerating it.

```bash
gem skill verify GEM_NAME [GEM_NAME ...]
```

This runs the same source-truth check as `--verify`, but never generates: the
gem must be installed (verification reads its source) and the skill must already
be cached. It errors if either is missing rather than generating a new skill.

```bash
# Verify the cached tty-spinner skill against its installed source
gem skill verify tty-spinner
```

Exit status matches `--verify`: `0` clean, `1` error, `2` when corrections were
applied. Verified versions are flagged with a green checkmark in
[`gem skill list`](#gem-skill-list).

---

### `gem skill --version`

Print the installed gem-skill version and exit.

```bash
gem skill --version
# 0.1.3
gem skill -v
# 0.1.3
```

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

Show all skills currently in the global cache. A green checkmark (`✓`) appears
next to any version whose skill has been verified against the gem's source (via
`--verify` or `gem skill verify`); unverified versions show no mark.

```bash
gem skill list
```

**Example output:**

```
Cached skills in /Users/you/.gem/skills:

  debug_me                       1.1.0
  faraday                        2.12.0, 2.14.3 ✓
  zeitwerk                       2.8.2 ✓

3 gem(s), 4 version(s) total.
```

Here `faraday 2.14.3` and `zeitwerk 2.8.2` have verified skills, while
`faraday 2.12.0` and `debug_me 1.1.0` have not been verified. The checkmark is
shown in green when the output is an interactive terminal, and as a plain `✓`
when piped or redirected. "Verified" means the skill was checked against the
gem's actual source — see [`gem skill verify`](#gem-skill-verify).

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
