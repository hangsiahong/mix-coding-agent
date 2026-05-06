# memorybank index

Content catalog — every page, one-line summary, grouped by category.
Update this file after every ingest or new page created.

---

## pages

| file | summary |
|---|---|
| architecture.md | Full component map: 38 source files, ~5240 lines, data flow, key design decisions |
| design-philosophy.md | 14-section deep dive: why bash, python3 not jq, cat build, regex repo map, context engineering (3 caches), 4-strategy edits, safety tiers, caveman mode, extensibility (skills/extensions/providers), memorybank compounding, cavekit specs, parallelism, self-hosting proof, decision record table |
| why-minimal.md | Defense of minimal claim: zero framework, line budget breakdown, dependency comparison |
| security.md | Security posture: all 4 critical audit issues resolved, risk scoring system, known limitations |
| tools-reference.md | 7 tools (bash/read/edit/create/list/search/global_memory), 4-strategy edit_file, parallel batching for read-only tools, processing pipeline |
| repl-commands.md | 25+ slash commands: cavekit, agent, workers, AFK, clipboard, input features |
| provider-system.md | Pluggable providers, defaults persistence, env vars, how to add custom providers |

## solutions

| file | summary |
|---|---|
| multi-language-adaptation.md | How `mix` auto-adapts to JS/TS (Next.js), Rust, Python using `auto_verify` and universal ctags AST parsing. Ready for production across stacks |
| tmux-detached-workers.md | Use of `tmux new-window -d` to prevent background tasks from stealing UI focus. Agent orchestration instructions in system prompt |
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
| token-tracking.md | Session token counters (prompt/completion/calls/cache). ctx_bar stats line with smart M/k format + cache % in purple. /stats shows cache tokens |
| test-generation.md | /test system: init (detect+install+scaffold), generate (targeted or recent), run, coverage. Background via --bg. 6 frameworks. |
| session-persistence.md | /resume session recovery. .agent/session.json saved on exit, restores file cache + repo map + env + config. Base64 encoding. 27 tests |
| tui-polish.md | 12 TUI improvements: flicker fix, turn progress, truncation marker, grouped /help, spinner colors, smart tab-complete, diff context, tmux ⟳ status. 15 tests |
| sandbox.md | Alpine chroot + Linux namespaces + cgroup v2. /sandbox commands, --sandbox flag, system prompt injection. Zero new deps. |
| versioning-self-heal.md | Versioned binary storage (~/.mix/versions/), health-gated builds, thin wrapper fallback, --self-test/--doctor/--version flags, auto-prune (keep 5) |
| prompt-optimization.md | System prompt audit: 43% reduction via global memory cap + self-cleanup + wiki/SPEC compression |
| elite_agent_upgrades.md | Ctags Repo Map, Proactive Memory, descriptive auto-commit messages. Hunk review stripped — yolo+/undo philosophy |
| mid-loop-compact.md | Fix: compact_history now checks every tool-use turn, not just at run_agent() entry. Prevents unbounded growth mid-loop |

## sources

| file | summary |
|---|---|
| codebase-audit-2025.md | Original audit (preserved). 4/4 critical fixed, 5/7 bugs fixed. See security.md for current posture |
| google-provider.md | Implementation of Google AI Studio and Vertex AI providers, OpenAI-compat headers, and region handling |- [Fix unescaped backticks in system prompt](solutions/fix-unescaped-backticks-in-system-prompt.md)
- [Fix shadowed compact command in REPL](solutions/fix-shadowed-compact-command-in-repl.md)
