# Installation

## Requirements

- Ruby >= 3.2.0
- At least one LLM provider API key (see [Configuration](configuration.md))

## Install the gem

```bash
gem install gem-skill
```

This makes the `gem skill` subcommand available immediately.

## Register the Bundler plugin

To enable `bundle skill` in your projects, run once after installation:

```bash
gem skill setup
```

This registers gem-skill as a Bundler plugin globally. You only need to do this
once per machine.

!!! tip "Alternative: per-project plugin"
    You can also add the plugin to a specific project's `Gemfile`:
    ```ruby
    plugin "gem-skill"
    ```
    This installs the plugin for that project only.

## Verify installation

```bash
# Check gem skill is available
gem skill

# Check bundle skill is available (after gem skill setup)
bundle skill
```

## Upgrading

```bash
gem update gem-skill
gem skill setup    # re-register the Bundler plugin with the new version
```

## Development installation

To run from source without building and releasing a gem:

```bash
git clone https://github.com/madbomber/gem-skill
cd gem-skill
bundle install
bin/dev_install    # points both Bundler plugin indexes at the source tree
```

`bin/dev_install --reset` restores the indexes to the last released gem.
