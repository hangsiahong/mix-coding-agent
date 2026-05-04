# memorybank index

Content catalog — every page, one-line summary, grouped by category.
Update this file after every ingest or new page created.

---

## pages

| file | summary |
|---|---|
| architecture.md | Full component map: 38 source files, ~5240 lines, data flow, key design decisions |
| design-philosophy.md | Why bash, why python3 not jq/node, why cat compilation, why regex not AST, why no framework |
| why-minimal.md | Defense of minimal claim: zero framework, line budget breakdown, dependency comparison |
| security.md | Security posture: all 4 critical audit issues resolved, risk scoring system, known limitations |
| tools-reference.md | 7 tools (bash/read/edit/create/list/search/global_memory), 4-strategy edit_file, parallel batching for read-only tools, processing pipeline |
| repl-commands.md | 25+ slash commands: cavekit, agent, workers, AFK, clipboard, input features |
| provider-system.md | Pluggable providers, defaults persistence, env vars, how to add custom providers |

## solutions

| file | summary |
|---|---|
| extension-system.md | Drop-in plugin system. ~/.mix/extensions/ + .mix/extensions/. Convention hooks (_init/_cmd/_tool/_on_edit/_on_create/_on_bash/_on_session/_on_shutdown). /ext [load\|unload\|create\|reload\|list]. 24 tests |
| repo-map-structural-awareness.md | Regex-based codebase map (~1200 tokens) injected into system prompt. Eliminates 2-3 orientation tool calls per task. 10-language support, mtime-cached, /refresh to rebuild |
| file-content-cache.md | Session-scoped file content cache surviving history compaction. Auto-caches on read/edit/create. ~1000 tokens in system prompt. /cache to inspect |
| auto-verify-post-edit.md | Auto syntax/lint/typecheck after every edit_file/create_file. 10 languages, graceful degradation. [VERIFY: FAILED] in tool result |
| copilot-provider.md | GitHub Copilot provider: device-flow OAuth, token cache, model list, streaming |
| tool_feedback_system.md | Enhanced TUI tool execution system with professional icons and resilience strategies |
| workers-and-parallelism.md | tmux workers vs subagents, limitations, source references |
| parallel-tool-batching.md | Parallel read-only tools via batch dir, append_raw_nosave, single disk flush, TUI de-duplication |
| edit-suggestions.md | [SUGGESTION] context on edit_file failure. Shows surrounding lines. Model self-corrects in 1 turn without re-read |
| smart-bash-truncation.md | 50/50 head+tail + error extraction from truncated middle. [KEY ERRORS] section preserves diagnostics |
| token-tracking.md | Session token counters (prompt/completion/calls). ctx_bar stats line. /stats REPL command |
| test-generation.md | /test system: init (detect+install+scaffold), generate (targeted or recent), run, coverage. Background via --bg. 6 frameworks. |
| session-persistence.md | /resume session recovery. .agent/session.json saved on exit, restores file cache + repo map + env + config. Base64 encoding. 27 tests |
| tui-polish.md | 12 TUI improvements: flicker fix, turn progress, truncation marker, grouped /help, spinner colors, smart tab-complete, diff context, tmux ⟳ status. 15 tests |

## sources

| file | summary |
|---|---|
| codebase-audit-2025.md | Original audit (preserved). 4/4 critical fixed, 5/7 bugs fixed. See security.md for current posture |
