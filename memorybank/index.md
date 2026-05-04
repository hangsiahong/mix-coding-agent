# memorybank index

Content catalog — every page, one-line summary, grouped by category.
Update this file after every ingest or new page created.

---

## pages

| file | summary |
|---|---|
| architecture.md | Full component map: 29 source files, 2735 lines, data flow, key design decisions |
| why-minimal.md | Defense of minimal claim: zero framework, line budget breakdown, dependency comparison |
| security.md | Security posture: all 4 critical audit issues resolved, risk scoring system, known limitations |
| tools-reference.md | 7 tools (bash/read/edit/create/list/search/global_memory), 4-strategy edit_file, parallel batching for read-only tools, processing pipeline |
| repl-commands.md | 25+ slash commands: cavekit, agent, workers, AFK, clipboard, input features |
| provider-system.md | Pluggable providers, defaults persistence, env vars, how to add custom providers |

## solutions

| file | summary |
|---|---|
| copilot-provider.md | GitHub Copilot provider: device-flow OAuth, token cache, model list, streaming |
| tool_feedback_system.md | Enhanced TUI tool execution system with professional icons and resilience strategies |
| workers-and-parallelism.md | tmux workers vs subagents, limitations, source references |
| parallel-tool-batching.md | Parallel read-only tools via batch dir, append_raw_nosave, single disk flush, TUI de-duplication |

## sources

| file | summary |
|---|---|
| codebase-audit-2025.md | Original audit (preserved). 4/4 critical fixed, 5/7 bugs fixed. See security.md for current posture |
