# mix

A minimal terminal coding agent. It is a single bash script. No heavy dependencies, just `bash`, `curl`, and `python3`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master/install.sh | bash
```

Run it from any folder:
```bash
mix
```

*Note: Needs a free [KConsole AI](https://koompi.cloud) key. Set `export KCONSOLE_API_KEY=your_key` in your shell.*

## Features

- **Tools**: Reads, edits, and searches files. Runs bash commands.
- **Caveman Mode**: Strips all AI chat fluff. Just gives you straight answers and code.
- **Skills**: Add markdown files to `~/.mix/skills/` to teach mix custom behaviors. Load them with `/skill <name>`.
- **Subagents & Workers**: Give mix background tasks. Run `/subagent <name> <task>` to spawn an independent AI worker in tmux, or `/worker <name> <cmd>` for long bash jobs.
- **Memory**: Create a `memorybank/` folder in your project. Mix will read and update markdown notes there to remember things between sessions.
- **Safety**: Stops dangerous bash commands and asks for confirmation. Auto-commits changes using git.

## Config Settings

Export these in your shell profile if you want to change defaults:

```bash
export KCONSOLE_API_KEY="your_key"
export AGENT_MODEL="glm-5"
export AGENT_MODE="fast"             # fast, deep, plan
export CAVEMAN_MODE="full"           # ultra, full, lite, off
export CTX_TOKENS=131072             # context window size limit
```

## Chat Commands

Type these inside the mix prompt:

| Command | What it does |
|---|---|
| `/skill <name>` | Load a skill file from `~/.mix/skills/` |
| `/skills` | List active skills |
| `/worker <name> <cmd>` | Run background bash task (needs tmux) |
| `/subagent <name> <task>`| Run background AI agent (needs tmux) |
| `/workers` | List all background jobs |
| `/flush` | Clear chat memory to free up context |
| `/compact` | Summarize history to shrink context |
| `/paste` | Insert clipboard text as hidden context (no screen flood) |
| `/caveman <level>` | Change AI chat fluff level |
| `/mode <level>` | Change reasoning (fast/deep/plan) |
| `/model <name>` | Swap the AI model |
| `/yolo` | Toggle command auto-confirm on/off |
| `/exit` | Quit |

## Keyboard Shortcuts

| Key | What it does |
|---|---|
| `Ctrl+V` | Paste clipboard as hidden token — shows `[paste N lines]`, full text sent to LLM invisibly |
| `Ctrl+Shift+V` | Raw paste — shows the actual text in your prompt (useful for editing before sending) |
| `Ctrl+E` | Open current prompt line in `$EDITOR` (default: vim) for multi-line editing |
| `Tab` | Autocomplete `/commands`, `@file` paths, and bash filenames |
| `Ctrl+C` | Cancel current AI turn, return to prompt (does not exit) |

## Project Overrides

If you want specific settings for a project folder, make an `.agent/rc.sh` file there:
```bash
MODEL="gpt-4o"
TEST_CMD="npm run test"
```