# Skill Files

A `SKILL.md` is a structured Markdown document that gives Claude Code deep,
practical knowledge about a Ruby gem. Claude reads it automatically when it is
present in `.claude/skills/`.

## Format

Every generated skill starts with a top-level heading identifying the gem and
version, then covers seven sections:

```markdown
# faraday v2.14.3

## Overview
What the gem does and when to reach for it.

## Installation
Exact Gemfile/gemspec lines and any required post-install steps.

## Core API
Key classes, methods, and options with real method signatures and return values.

## Common Patterns
The 3–5 most frequent real-world usage patterns with working code examples.

## Gotchas & Edge Cases
Surprising defaults, version-specific behavior, thread safety, encoding issues.

## Configuration
Initializer patterns, environment variables, defaults worth knowing.

## Testing
How to test code that uses this gem: mocks, fakes, fixtures, VCR patterns.
```

## What Claude does with it

When Claude Code opens a project containing `.claude/skills/`, it reads every
`SKILL.md` it finds. This means:

- Claude knows the correct API for the exact version you're using
- No token cost re-deriving usage from READMEs mid-conversation
- The knowledge persists across conversation turns
- Multiple gems can be in scope simultaneously

## Sources used to generate

The LLM is given up to three sources per gem (in priority order):

1. **Local README + CHANGELOG** — from the gem's install directory
2. **RubyGems API** — summary, dependencies, source URI
3. **GitHub raw README** — fetched when not installed locally

Content is synthesized, not copied verbatim. The model is instructed to write
as a knowledgeable colleague, not a marketing document.

## Quality and regeneration

Skill quality depends on the documentation available for the gem and the model
used. For gems with poor upstream documentation, results will reflect that.

To improve a skill:

```bash
# Use a more capable model
gem skill install my_gem --force --model claude-opus-4-8

# Or set it as the default
export GEMSKILL_MODEL="claude-opus-4-8"
gem skill install my_gem --force
```

## Version specificity

Skills are cached per version. `faraday 2.12.0` and `faraday 2.14.3` each get
their own `SKILL.md`. Symlinks in `.claude/skills/` point to the version
matching your `Gemfile.lock`, so Claude always has the right version context.
