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

## 7. Adding a New Feature (Core)
1. Edit the relevant `src/*.sh` file.
2. New tool: add JSON schema to `src/10_tools_*.sh` + `case` in `src/13_tool_execution.sh`.
3. New `/command`: add `case` in `src/25_repl_commands.sh` + update the `/help` line.
4. Rebuild: `./build.sh`

## 8. Skills
Skills are Markdown files in `~/.mix/skills/`. Load with `/skill <name>` (filename without `.md`).
They are injected into the system prompt for the current session only.
To create a new skill: write a `.md` file to `~/.mix/skills/<name>.md`.

## 9. Extensions (Drop-in Plugins)

Extensions customize the harness without editing source. Drop a `.sh` file, load it, keep going.

### Directories
- **Global**: `~/.mix/extensions/<name>.sh` — available in every project
- **Project**: `.mix/extensions/<name>.sh` — project-local, **overrides** global (same name wins)

### Convention Hooks
Define functions following `<name>_<hook>`:

| Hook | Signature | When | Return |
|------|-----------|------|--------|
| `<name>_init` | `()` | On load | — |
| `<name>_cmd` | `(input)` | Before built-in REPL commands | `0` = handled, `1` = pass |
| `<name>_tool` | `(name, json_args)` | Before "unknown tool" fallback | Print result string, or `return 1` |
| `<name>_on_edit` | `(path)` | After successful `edit_file` | — |
| `<name>_on_create` | `(path)` | After successful `create_file` | — |
| `<name>_on_bash` | `(command)` | After successful `bash` execution | — |
| `<name>_on_session` | `()` | Session save/restore | — |
| `<name>_on_shutdown` | `()` | EXIT trap | — |

### Dispatch Priority
1. Extensions dispatched **before** built-in commands — they get first crack
2. Extension tools dispatched **before** unknown-tool fallback in `process_tc()`
3. Project extensions override global (same basename)

### Auto-Load
Extensions auto-load on startup via `_ext_load_all()`. No manual step needed.

### REPL Commands
| Command | Action |
|---------|--------|
| `/ext load <name>` | Load a single extension |
| `/ext unload <name>` | Unload (calls `_on_shutdown`, unsets functions) |
| `/ext create <name>` | Scaffold template in `~/.mix/extensions/` |
| `/ext reload` | Reload all extensions |
| `/ext list` | Show loaded + available extensions |

### Extension Template (`/ext create <name>` generates this)
```bash
# ~/.mix/extensions/myext.sh

MYEXT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

myext_init() {
  : # setup on load
}

myext_cmd() {
  # Return 0 = handled (stop dispatch), 1 = pass to next handler
  case "$1" in
    /myext)        echo "Hello!"; return 0 ;;
    /myext\ *)     echo "Got: ${1#/myext }"; return 0 ;;
  esac
  return 1
}

myext_tool() {
  # $1 = tool name, $2 = json args. Print result or return 1.
  case "$1" in
    my_custom_tool)
      echo '{"result":"handled"}'
      return 0
      ;;
  esac
  return 1
}

myext_on_edit() {
  local _path="$1"
  # e.g. auto-lint after edit
  case "$_path" in
    *.sh) shellcheck "$_path" 2>&1 || true ;;
    *.py) python3 -m py_compile "$_path" 2>&1 || true ;;
  esac
}

myext_on_create() {
  local _path="$1"
  : # e.g. auto-format new files
}

myext_on_bash() {
  local _cmd="$1"
  : # e.g. log commands, notify on long jobs
}

myext_on_shutdown() {
  : # cleanup temp files, etc
}
```

### How to Help Users Build Extensions
When a user asks to build an extension:
1. **Identify the hook they need** — most common:
   - New REPL command → `_cmd`
   - Auto-action after edits → `_on_edit`
   - Custom tool for LLM → `_tool` (also needs schema in `src/10_tools_*.sh` unless pure dispatch)
   - Background process on startup → `_init`
   - Cleanup → `_on_shutdown`
2. **Create the file** — write to `~/.mix/extensions/<name>.sh` or `.mix/extensions/<name>.sh`
3. **Load it** — `/ext load <name>` (or restart mix)
4. **Test it** — exercise the hook and verify behavior
5. **Common patterns**:
   - Lint on save: `_on_edit` + `shellcheck`/`py_compile`
   - Custom deploy: `_cmd` matches `/deploy` → runs deploy script
   - Notification: `_on_bash` watches for long commands, sends alert
   - Project guard: `_on_edit` blocks edits outside project dir
   - Test runner integration: `_on_edit` runs related tests
6. **Limitations** (current):
   - No hot-reload on file change — must `/ext reload` or restart
   - No extension config file — use variables in the script
   - `_tool` only handles dispatch; adding LLM-visible tools still requires schema edit in core
   - Extensions share the same bash process — no isolation

### Integration Points (for core contributors)
- `src/04b_extension_system.sh` — all extension logic
- `src/25_repl_commands.sh` — `_ext_dispatch_cmd()` call before built-in `case`
- `src/22_process_one_tool_call.sh` — `_ext_dispatch_tool()` + `_ext_hook on_edit/on_create/on_bash`
- `src/27_main_repl.sh` — `_ext_hook on_shutdown` in EXIT trap + tab-completion
- `build.sh` — load order: `04_project_local → 04b_extension_system → 05_pre_edit_diff_preview`

## 10. .mixrc (Project Config)
`.mixrc` files live in project roots (walks parent dirs). 16 whitelisted keys:

```
MODEL BASE_URL PROVIDER CAVEMAN_MODE AGENT_MODE AUTO_YES CTX_TOKENS
TEST_CMD LINT_CMD VERIFY_CMD BUILD_CMD EXTRA_SYSTEM MAX_TURNS
TOOL_TIMEOUT SPINNER_CHARS RISK_THRESHOLD
```

Priority: env vars (`AGENT_MODEL`, `AGENT_BASE_URL`, `AGENT_PROVIDER`) > `.mixrc` > defaults from `01_config.sh`.
Only the 3 proxied keys (MODEL/BASE_URL/PROVIDER) check env vars — the other 13 apply unconditionally from `.mixrc`.