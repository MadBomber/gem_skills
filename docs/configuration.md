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
