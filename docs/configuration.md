# Configuration

## LLM provider API keys

gem-skill uses [RubyLLM](https://github.com/crmne/ruby_llm) to generate skills.
Set at least one provider API key before running any `install` command:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."   # Claude models
export OPENAI_API_KEY="sk-..."          # GPT models
export GEMINI_API_KEY="..."             # Gemini models
```

Other supported providers:

| Environment variable    | Provider     |
|------------------------|--------------|
| `ANTHROPIC_API_KEY`    | Anthropic    |
| `OPENAI_API_KEY`       | OpenAI       |
| `GEMINI_API_KEY`       | Google Gemini|
| `MISTRAL_API_KEY`      | Mistral      |
| `DEEPSEEK_API_KEY`     | DeepSeek     |
| `OPENROUTER_API_KEY`   | OpenRouter   |
| `XAI_API_KEY`          | xAI (Grok)   |

## gem-skill environment variables

### `GEMSKILL_DIR`

Controls where generated skills are cached.

| | |
|---|---|
| **Default** | `~/.gem/skills` |
| **Example** | `export GEMSKILL_DIR="/Volumes/shared/gem-skills"` |

Useful for sharing a skill cache across machines via a network drive, or for
keeping skills in a non-standard location.

### `GEMSKILL_PROJECT_DIR`

The project-relative directory where `bundle skill` writes its symlinks into the
cache. Change it to match whichever assistant you use.

| | |
|---|---|
| **Default** | `.claude/skills` (Claude Code) |
| **Example** | `export GEMSKILL_PROJECT_DIR=".agents"` |

`SKILL.md` is a shared format, but each assistant looks for skills in its own
project directory:

| Assistant    | Suggested `GEMSKILL_PROJECT_DIR` |
|--------------|----------------------------------|
| Claude Code  | `.claude/skills` (default)       |
| OpenAI Codex | `.agents` or `.codex`            |

```bash
# Claude Code (default — no need to set anything)
bundle skill install

# OpenAI Codex — link into a Codex project root instead
export GEMSKILL_PROJECT_DIR=".agents"
bundle skill install        # symlinks now land in .agents/
```

A blank or unset value falls back to the `.claude/skills` default.

!!! note "Availability is not activation"
    Setting `GEMSKILL_PROJECT_DIR` controls *where the symlinks are written*. It
    does not change how an assistant decides a skill is active. Claude Code
    activates every `SKILL.md` under `.claude/skills/` automatically; other
    assistants (e.g. Codex) may require the skill to be in the session's
    available-skills list or referenced explicitly. See
    [Using with other assistants](skill-files.md#using-with-other-assistants).

### `GEMSKIL_MAX_TOKENS`

Controls the maximum number of output tokens the LLM may generate for each skill file.
Increase this if generated `SKILL.md` files are being truncated.

| | |
|---|---|
| **Default** | `32767` |
| **Example** | `export GEMSKIL_MAX_TOKENS=65536` |

### `GEMSKILL_TEMPERATURE`

Sampling temperature for generation. Lower values produce more consistent,
deterministic output — appropriate for factual reference documentation.

| | |
|---|---|
| **Default** | `0.2` |
| **Example** | `export GEMSKILL_TEMPERATURE=0.0` |

Only applied to models that support a temperature parameter. Reasoning models
(e.g. `gpt-5.5`) reject it, so the value is silently skipped for them — switch to
a temperature-supporting model (Claude, Gemini, older GPT) to benefit.

### `GEMSKILL_MODEL`

Controls which LLM model is used when generating skills.

| | |
|---|---|
| **Default** | `gpt-5.5` |
| **Example** | `export GEMSKILL_MODEL="claude-opus-4-8"` |

The `--model` flag on any command overrides `GEMSKILL_MODEL` for that single
invocation only.

## Recommended shell configuration

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export GEMSKILL_MODEL="claude-sonnet-4-6"   # or whichever model you prefer
```

## Model selection guidance

| Model | Best for |
|-------|----------|
| Claude Opus 4.8 | Highest quality skills; comprehensive coverage |
| Claude Sonnet 4.6 | Good balance of quality and speed |
| Claude Haiku 4.5 | Fast, cheap; good for simple gems |
| GPT-5.5 | Default; strong general-purpose coverage |

Pass `--model MODEL` to any install command to override for one run:

```bash
gem skill install rails --model claude-opus-4-8
bundle skill install --model claude-haiku-4-5
```
