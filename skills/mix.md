# 🛠️ mix-skill: Extending and Hacking Mix

## 1. What is Mix?
`mix` is a compiled single-file Bash/Python terminal coding agent with no heavy dependencies.
- The compiled binary is `mix`. **Never edit `mix` directly.**
- All source lives in `src/*.sh`. Edit there, then rebuild with `./build.sh`.
- Build output: `mix.compiled` (copy) and `mix` — both updated automatically.

## 2. Key Source Files
| File | Purpose |
|------|---------|
| `src/01_config.sh` | Global config, defaults, provider activation, `MIX_YOLO` |
| `src/03_system_prompt_*.sh` | `build_system_prompt()` — caveman mode, skills injection |
| `src/10_tools_*.sh` | OpenAI-compatible tool JSON schemas (what the LLM sees) |
| `src/13_tool_execution.sh` | Implements each tool call: `edit_file`, `bash`, `read_file`, etc. |
| `src/14_risk_scoring_*.sh` | `score_risk()` — blocks/warns on dangerous bash commands |
| `src/16_api.sh` | Non-streaming API call via `curl` |
| `src/18_streaming_api_call.sh` | Streaming via Python `urllib`, writes live to `/dev/tty` |
| `src/22_process_one_tool_call.sh` | Dispatches each tool call, manages `FAIL_STREAK` |
| `src/23_lightweight_planning_call_*.sh` | `/mode plan` — lightweight pre-flight plan call |
| `src/24_agent_loop_*.sh` | Core loop: call API → parse → execute tools → repeat |
| `src/25_repl_commands.sh` | All `/commands`: `/afk`, `/spec`, `/worker`, `/skill`, etc. |
| `src/27_main_repl.sh` | `read -e` REPL loop, paste handling, interactive detection |
| `src/29_telegram.sh` | Telegram integration for AFK approval flow |
| `src/providers/*.sh` | Provider adapters: `copilot.sh`, `kconsole.sh`, etc. |

## 3. Slash Commands Reference
| Command | What it does |
|---------|--------------|
| `/model [id]` | Switch model. Validates against provider's model list. |
| `/models` | List available models for current provider |
| `/provider [name]` | Switch provider (copilot, kconsole, openai, anthropic) |
| `/mode [fast\|deep\|plan]` | Change reasoning depth |
| `/caveman [off\|lite\|full\|ultra]` | Restrict LLM to read-only or no-tool mode |
| `/yolo` | Toggle AUTO_YES (skip all confirmations) |
| `/flush` | Clear conversation history |
| `/compact` | Summarize history to save tokens |
| `/spec <idea>` | Start a Cavekit spec-driven project |
| `/worker <name> <cmd>` | Spawn a named background worker in tmux |
| `/subagent <name> <task>` | Run a subagent with a specific task |
| `/afk [hint]` | Background analysis → plan written to `~/.mix/afk-plan.md`, sent via Telegram |
| `/afk setup` | Interactive Telegram bot setup |
| `/afk apply` | Apply the saved AFK plan |
| `/afk log` | Show current saved plan |
| `/afk stop` | Kill the AFK tmux window |
| `/skill <name>` | Inject a skill file into context |
| `/skills` | List available skills |
| `/history` | Show conversation history |
| `/help` | Full command reference |

## 4. User Config (~/.mix/)
| Path | Purpose |
|------|---------|
| `~/.mix/defaults` | Persisted `PROVIDER`, `MODEL`, `BASE_URL` across sessions |
| `~/.mix/rc.sh` | User startup overrides (sourced on every mix start — trusted) |
| `~/.mix/skills/*.md` | Skill files, loadable with `/skill <name>` |
| `~/.mix/telegram` | Telegram bot token + chat ID for AFK approval (chmod 600) |
| `~/.mix/afk-plan.md` | Latest plan written by `/afk` |
| `~/.mix/memory.md` | Global persistent memory (updated via `update_global_memory` tool) |

## 5. RC File (~/.mix/rc.sh)
`~/.mix/rc.sh` is sourced every time mix starts. Use it for personal defaults and overrides.

To create one:
```bash
touch ~/.mix/rc.sh
chmod 600 ~/.mix/rc.sh
```

Example contents:
```bash
# ~/.mix/rc.sh

# Always default to a specific model
MODEL=claude-sonnet-4-5

# Skip confirmations by default
AUTO_YES=true

# Append to the system prompt
EXTRA_SYSTEM="Be concise. Prefer editing existing files over creating new ones."
```

**Security note:** Only `~/.mix/rc.sh` is auto-sourced. Project-local `.agent/rc.sh` files are NOT loaded — untrusted working directories could abuse auto-sourcing.

## 6. Providers
- **copilot** — GitHub Copilot subscription. Run `/provider copilot login`. Endpoint auto-detected.
- **kconsole** — KConsole AI Gateway. Set `KCONSOLE_API_KEY`.
- **openai** — Set `OPENAI_API_KEY`.
- **anthropic** — Set `ANTHROPIC_API_KEY`.

## 7. Adding a New Feature
1. Edit the relevant `src/*.sh` file.
2. New tool: add JSON schema to `src/10_tools_*.sh` + `case` in `src/13_tool_execution.sh`.
3. New `/command`: add `case` in `src/25_repl_commands.sh` + update the `/help` line.
4. Rebuild: `./build.sh`

## 8. Skills
Skills are Markdown files in `~/.mix/skills/`. Load with `/skill <name>` (filename without `.md`).
They are injected into the system prompt for the current session only.
To create a new skill: write a `.md` file to `~/.mix/skills/<name>.md`.