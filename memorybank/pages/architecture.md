# Mix Architecture

## Overview
~5240 lines bash across 38 source files + 1 provider. Compiled to single binary `mix` via `build.sh`. Single-process, multi-turn agent loop with streaming. 166 bats tests.

## Component Map

| File | Lines | Role |
|---|---|---|
| 00_header.sh | 8 | Comment header |
| 01_config.sh | 125 | Config, defaults, provider system, env vars, session token counters |
| 02_mixrc.sh | 107 | _mixrc_load(): walks parent dirs for .mixrc, 16 whitelisted keys. Project overrides defaults, env vars override .mixrc for proxied keys |
| 02_tmux_bootstrap.sh | 14 | Auto-launch/attach tmux session (bypass: MIX_NO_TMUX=1) |
| 03_system_prompt_*.sh | 185 | build_system_prompt(): rebuilt per call, injects wiki/cavekit/global memory/skills |
| 04_project_local_extensions.sh | 7 | Sources ~/.mix/rc.sh only (project .agent/rc.sh removed for security) |
| 04b_extension_system.sh | 245 | Drop-in plugins: ~/.mix/extensions/ + .mix/extensions/. Convention hooks (_init, _cmd, _tool, _on_edit, _on_create, _on_bash, _on_session, _on_shutdown). REPL: /ext [load\|unload\|create\|reload\|list] |
| 05_pre_edit_diff_preview.sh | 48 | show_edit_diff(): colored unified diff + context lines with line numbers before edit confirmation |
| 06_auto_read_logs_on_bash_failure.sh | 15 | auto_read_logs(): extracts .log/.err/.out paths from error, tails last 20 lines |
| 07_environment_detection.sh | 37 | detect_env(): git branch, node/go/rust/python/docker detection, test runner detection. Calls session_load() |
| 08a_failure_diagnostics.sh | 130 | diagnose_failure(): pattern-matches common errors (command not found, permission denied, etc) |
| 08_self_healing_bash_wrapper.sh | 65 | run_with_heal(): bash -c + auto-retry. Smart output truncation (50/50 + error extraction) with `┊ showing first/last N of N lines ┊` marker |
| 09_wiki_solutions_writer.sh | 20 | write_wiki_solution(): auto-creates solution md in memorybank/solutions/ |
| 10_tools_openai_function_calling.sh | 3 | TOOLS_JSON: 7 tools (bash, read_file, create_file, edit_file, list_files, search_files, update_global_memory) |
| 11a_file_cache.sh | 146 | file_cache_put/del/validate(): session-scoped file content cache. build_file_context() for system prompt injection. ~1000 token budget |
| 11b_repo_map.sh | 217 | build_repo_map(): regex-based code structure map. 10 languages, mtime-cached, ~1500 token budget. Injected into system prompt. /refresh to rebuild |
| 11c_session.sh | 232 | session_save/load/apply/clear(): persistence across restarts. Base64 encoding for safe field passing. /resume restores file cache + repo map + env + config |
| 11_history.sh | 20 | JSON history load/save, API key redaction via sed |
| 12_auto_compact_history.sh | 188 | compact_history(): LLM summarizes old messages, keeps last 10 verbatim. append_raw(): python3 JSON append via stdin pipe |
| 13a_auto_verify.sh | 201 | _get_verify_cmds()/auto_verify(): post-edit syntax/lint/typecheck. 10 languages (sh, py, js/ts, rs, go, rb, java, c/cpp). [VERIFY: FAILED] in tool result |
| 13_tool_execution.sh | 260 | run_tool(): pure tool dispatch. edit_file has 4-strategy fuzzy matching + [SUGGESTION] context on failure. spawn_subagent support |
| 14_risk_scoring_*.sh | 48 | score_risk(): BLOCKED/HIGH/MED/LOW. Scans full command for fork-bombs, rm, sudo-destruct, remote-exec, pkg-install, git-write, file-write |
| 15_ask_user_for_confirmation_*.sh | 12 | confirm(): reads /dev/tty (not stdin), respects AUTO_YES |
| 16_api.sh | 52 | call_api(): non-streaming API call |
| 17_response_parser.sh | 23 | parse_resp(): RAW/TC/TEXT protocol format |
| 18_streaming_api_call.sh | 227 | call_api_stream(): SSE streaming with spinner kill, network-drop retry fallback. Skip re-render for ≤8 lines, safe over-count for long |
| 19_spinner_*.sh | 29 | start_spinner()/stop_spinner(): braille animation. Orange for *retry*, red for *error*/recovery* |
| 20_context_window_bar.sh | 23 | ctx_bar(): token usage bar (3 chars/token ratio) + session stats line (API calls, prompt/completion tokens) |
| 21_tmux_status_updater.sh | 27 | tmux_update(): refreshes tmux status bar with context % + ⟳ when spinner active |
| 22_process_one_tool_call.sh | 258 | process_tc(): UX layer per tool — risk scoring, confirmation, diff preview, git commit, test runner. MED risk shows [yolo: auto-confirmed] |
| 23_lightweight_planning_*.sh | 28 | call_api_plan(): lightweight planning call, shows numbered plan, asks approval |
| 24_agent_loop_*.sh | 221 | run_agent(): main loop. Parallel read-only tools via batch dir + append_raw_nosave. ctx_bar before first turn. Turn progress indicator. 3x API retry. Token tracking |
| 25_repl_commands.sh | 755 | handle_cmd(): 25+ slash commands. Grouped /help. Cavekit (/spec, /build, /check). AFK mode. Workers/subagents. Provider/model switching. Skills. Paste. /undo. /stash. /stats |
| 26a_test_commands.sh | 568 | /test system: init (detect+install+scaffold), generate (targeted or recent), run, coverage. Background via --bg. 6 frameworks |
| 26_banner.sh | 30 | Startup banner with keybinding hints (Tab, Ctrl+E, Ctrl+V) |
| 27_main_repl.sh | 266 | Main REPL. Interactive (readline with smart tab-complete for /commands/@files only, Ctrl+V paste, Ctrl+E editor, turn separator). EXIT trap saves session + cleans up |
| 29_telegram.sh | 66 | Telegram bot setup (device-flow style). AFK approval via inline buttons + 2h poll timeout |
| providers/copilot.sh | 332 | GitHub Copilot provider: device-flow OAuth, token cache, model list, streaming |

## Data Flow
```
User input → append_text("user") → [plan mode?] → while turns < MAX_TURNS (100):
  → call_api_stream() → parse_resp() → classify tools (read-only vs write)
  → [Parallel batch]: read_file/list_files/search_files run concurrently in subshells
    → results → temp batch dir → append_raw_nosave() per tool → single save_history flush
  → [Sequential batch]: bash/edit_file/create_file run one-by-one via process_tc()
    → process_tc → score_risk → confirm → run_tool() → append_raw("tool")
  → ctx_bar + tmux_update + memorybank log append
```

## Key Design Decisions
- **bash -c not eval**: all command execution via bash -c, no eval on LLM output
- **python3 for JSON only**: stdlib only, no pip, used via one-liner pipes
- **stdin pipe for large payloads**: append_raw passes history via stdin to python3, avoids ARG_MAX
- **API key redaction**: save_history sed-replaces KCONSOLE_API_KEY before writing
- **Trusted rc only**: only ~/.mix/rc.sh sourced, not project-local
- **Extension system**: pi.dev-style drop-in plugins via convention hooks. Project extensions override global. 24 tests.
- **3x API retry with streaming fallback**: network drop → retry without streaming → retry → fail
- **Batch history I/O**: parallel tool results appended in-memory via append_raw_nosave(), flushed once per batch to disk
- **MAX_TURNS=100**: up from 30. Supports longer agent sessions without premature cutoff
- **Edit failure suggestions**: [SUGGESTION] context on edit mismatch eliminates re-read turn
- **Smart bash truncation**: 50/50 head/tail + error extraction preserves diagnostic signal from middle
- **Token tracking**: session counters for prompt/completion tokens, displayed in ctx_bar and /stats
