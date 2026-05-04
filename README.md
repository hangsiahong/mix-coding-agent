# mix

A minimal terminal coding agent. Single bash script, ~4700 lines. No heavy dependencies — just `bash`, `curl`, and `python3`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master/install.sh | bash
```

Run it from any folder:
```bash
mix
```

*Note: Needs a free [KConsole AI](https://koompi.cloud) key. Set `export KCONSOLE_API_KEY=your_key` in your shell — or use GitHub Copilot (see [Providers](#providers) below).*

## Features

- **Tools**: `read_file`, `edit_file`, `create_file`, `list_files`, `search_files`, `bash` — full coding agent toolset.
- **Streaming**: Tokens stream live. Context window bar shows usage in real-time.
- **Providers**: Swap between KConsole (default) and **GitHub Copilot** (gpt-4o, claude-sonnet, gemini, and more — free with a Copilot subscription).
- **Caveman Mode**: Strips all AI chat fluff. Four levels: `ultra`, `full`, `lite`, `off`. Just answers and code.
- **Skills**: Add markdown files to `~/.mix/skills/` to teach mix custom behaviors. Load them with `/skill <name>`.
- **Subagents & Workers**: Give mix background tasks. `/subagent <name> <task>` spawns an independent AI worker in tmux, `/worker <name> <cmd>` for long bash jobs.
- **Session Resume**: Saves file cache, repo map, env info, and config on exit. `/resume` restores it next session — no re-orientation needed.
- **Memorybank**: Three-layer wiki (`raw/` → `memorybank/` → `AGENTS.md`). Mix reads and updates markdown notes to compound knowledge across sessions.
- **Safety**: Risk-gated shell execution (BLOCKED/HIGH/MED/LOW). Auto-commits every edit with git. Diff preview before applying changes.
- **Auto-Verify**: After edits, auto-runs syntax check, linter, and typechecker (10 languages). Catches bugs immediately.
- **Extensions**: Drop-in plugins. Put `.sh` in `~/.mix/extensions/` or `.mix/extensions/`. Convention hooks customize the harness without forking. See [Extensions](#extensions).
- **Self-Healing Bash**: Failed commands get automatic diagnostics and recovery hints. Streak detection with fallback suggestions.
- **Repo Map**: Aider-style code structure map injected into system prompt. Eliminates 2-3 orientation turns per task.
- **File Cache**: Caches read file contents in-memory, auto-injects into system prompt. Survives history compaction.
- **Spec-Driven Builds**: `/spec` defines features with §G/§C/§I/§V/§T sections. `/build` executes tasks. `/check` detects drift.
- **Test Runner**: `/test init` detects framework and scaffolds tests. `/test generate` creates tests from source. `/test run` and `/test coverage` for execution.
- **Context Engineering**: `/compact` summarizes history. `/flush` clears it. Token tracking with `/stats`. History compaction preserves file cache.

## Providers

mix supports pluggable API providers. The active provider and model are saved to `~/.mix/defaults` and restored on next start.

### Default (KConsole)

```bash
export KCONSOLE_API_KEY="your_key"
```

### GitHub Copilot

Use your existing Copilot subscription — no extra key needed.

```
/provider copilot login    # one-time OAuth (opens browser)
/provider copilot          # activate for this session + save as default
/models                    # list available models
/model claude-sonnet-4.5   # pick one
```

Supported models include: `gpt-4o`, `gpt-4.1`, `claude-sonnet-4.6`, `claude-opus-4.7`, `gemini-3.1-pro-preview`, and more.

To reset back to default:
```
/provider default
```

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
| `/resume` | Restore saved session (file cache, repo map, config) |
| `/skill <name>` | Load a skill file from `~/.mix/skills/` |
| `/skills` | List active skills |
| `/worker <name> <cmd>` | Run background bash task (needs tmux) |
| `/subagent <name> <task>` | Run background AI agent (needs tmux) |
| `/workers` | List all background jobs |
| `/flush` | Clear chat history + session |
| `/compact` | Summarize history to shrink context |
| `/paste` | Insert clipboard text as hidden context (no screen flood) |
| `/caveman <level>` | Change AI chat fluff level (`ultra`/`full`/`lite`/`off`) |
| `/mode <level>` | Change reasoning (`fast`/`deep`/`plan`) |
| `/model <name>` | Swap the AI model |
| `/models` | List all models available from current provider |
| `/provider <name>` | Switch provider (e.g. `copilot`, `default`) |
| `/yolo` | Toggle command auto-confirm on/off |
| `/test init` | Detect test framework, install, scaffold first tests |
| `/test generate` | Generate tests for a file or recent edits |
| `/test run` | Run tests |
| `/test coverage` | Run tests with coverage |
| `/spec` | Show current spec |
| `/build` | Execute spec tasks |
| `/check` | Detect spec drift (zero writes) |
| `/stats` | Show session token usage |
| `/undo` | `git revert HEAD` — undo last commit |
| `/stash` | `git stash` — stash current changes |
| `/history` | Show recent conversation history |
| `/cache` | Show file cache contents |
| `/verify` | Show auto-verify status |
| `/afk setup` | Configure Telegram notifications for long-running tasks |
| `/refresh` | Invalidate repo map (forces rebuild) |
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

## Architecture

mix is built from 35 source files concatenated by `build.sh` into a single executable:

```
src/
├── 01_config.sh              # provider/model defaults, key loading
├── 03_system_prompt.sh       # system prompt builder (picks up caveman mode)
├── 05_pre_edit_diff.sh       # diff preview before edits
├── 06_auto_read_logs.sh      # auto-attach logs on bash failure
├── 07_environment_detection.sh  # git, node, python, tool detection
├── 08a_failure_diagnostics.sh   # error pattern matching + diagnosis
├── 08_self_healing_bash.sh      # auto-retry with hints on failure
├── 09_wiki_solutions.sh      # memorybank solution writer
├── 11a_file_cache.sh         # in-memory file content cache
├── 11b_repo_map.sh           # Aider-style code structure map
├── 11c_session.sh            # session save/load/resume across restarts
├── 11_history.sh             # conversation history persistence
├── 12_auto_compact.sh        # auto-compact history on context overflow
├── 13a_auto_verify.sh        # post-edit syntax/lint/typecheck
├── 13_tool_execution.sh      # tool dispatch + execution
├── 14_risk_scoring.sh        # BLOCKED/HIGH/MED/LOW risk gating
├── 15_ask_user.sh            # confirmation prompts (reads /dev/tty)
├── 16_api.sh                 # API call wrapper
├── 17_response_parser.sh     # parse LLM response → tool calls + text
├── 18_streaming_api.sh       # SSE streaming with live token output
├── 19_spinner.sh             # background spinner process
├── 20_context_bar.sh         # context window usage bar
├── 21_tmux_status.sh         # tmux status line integration
├── 22_process_tool_call.sh   # process one tool call (edit/bash/read)
├── 23_plan_mode.sh           # lightweight planning call
├── 24_agent_loop.sh          # main agent loop (multi-turn tool use)
├── 25_repl_commands.sh       # all /command handlers
├── 26a_test_commands.sh      # /test init/generate/run/coverage
├── 29_telegram.sh            # Telegram notification integration
└── providers/copilot.sh      # GitHub Copilot provider
```