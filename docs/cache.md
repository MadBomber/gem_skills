# Cache

## Location

The global skill cache lives at `~/.gem/skills` by default. Override with:

```bash
export GEMSKILL_DIR="/path/to/your/cache"
```

## Structure

```
~/.gem/skills/
├── debug_me/
│   └── 1.1.0/
│       ├── SKILL.md
│       └── metadata.json
├── faraday/
│   ├── 2.12.0/
│   │   ├── SKILL.md
│   │   └── metadata.json
│   └── 2.14.3/
│       ├── SKILL.md
│       └── metadata.json
└── zeitwerk/
    └── 2.8.2/
        ├── SKILL.md
        └── metadata.json
```

Each gem can have multiple cached versions. They coexist without conflict — two
projects pinning different versions of the same gem each get the correct skill.

## Files

### `SKILL.md`

The generated skill file. Contains structured documentation tailored for
Claude Code. See [Skill Files](skill-files.md) for the format.

### `metadata.json`

Stores provenance information:

```json
{
  "gem_name": "faraday",
  "version": "2.14.3",
  "model": "claude-sonnet-4-6",
  "generated_at": "2026-06-17T10:23:45Z",
  "sources": ["readme", "changelog", "rubygems"]
}
```

## Cache commands

```bash
# List everything in the cache
gem skill list

# Remove a specific version
gem skill purge faraday 2.12.0

# Remove all versions of a gem
gem skill purge faraday --all
```

## Sharing the cache

You can share a skill cache across machines by pointing `GEMSKILL_DIR` at a
shared location:

```bash
# Team-shared network drive
export GEMSKILL_DIR="/Volumes/team-shared/gem-skills"
```

All machines with the same `GEMSKILL_DIR` will read and write to the same cache.
Skills generated on one machine are immediately available on others.

## Project symlinks

Projects don't store skills locally — they hold symlinks into the global cache:

```
your-project/.claude/skills/
├── faraday  →  ~/.gem/skills/faraday/2.14.3/
└── zeitwerk →  ~/.gem/skills/zeitwerk/2.8.2/
```

Each symlink points to the **version directory**. Claude Code reads `SKILL.md`
from inside the linked directory.

`bundle skill refresh` updates symlinks when versions change after `bundle update`.
`bundle skill list` shows the status of all current symlinks.

## Regenerating skills

Skills do not auto-expire. Regenerate explicitly when you want updated content:

```bash
# Regenerate one gem
gem skill install faraday --force

# Regenerate all project gems with a better model
bundle skill install --force --model claude-opus-4-8
```
