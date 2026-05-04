# TUI Polish (12 improvements)

## What
12 TUI improvements across streaming, REPL, diff preview, spinner, and tmux integration.

## Changes

| # | Feature | File |
|---|---|---|
| 1 | Re-render flicker fix: skip for ≤8 lines, safe over-count (+4) for long | `18_streaming_api_call.sh` |
| 2 | Turn progress: `⤷ turn N · N tools · Nk tokens` after tool batch | `24_agent_loop.sh` |
| 3 | Bash truncation marker: `┊ showing first/last N of N lines (N omitted) ┊` | `08_self_healing_bash_wrapper.sh` |
| 4 | Banner keybinding hints: Tab=complete Ctrl+E=editor Ctrl+V=paste | `26_banner.sh` |
| 5 | Grouped /help: Session/Safety/Config/Cavekit/Testing/Workers/Skills | `25_repl_commands.sh` |
| 6 | MED risk yoyo indicator: `[yoyo: auto-confirmed]` when AUTO_YES=true | `22_process_one_tool_call.sh` |
| 7 | ctx_bar before first turn: early context budget warning | `24_agent_loop.sh` |
| 8 | Spinner color states: orange for *retry*, red for *error*/recovery* | `19_spinner.sh` |
| 9 | Smart tab-complete: /commands + @files only, no regular text noise | `27_main_repl.sh` |
| 10 | Turn separator: dim `───` line between agent turns | `27_main_repl.sh` |
| 11 | Diff preview context: surrounding lines with line numbers + `▸` marker | `05_pre_edit_diff_preview.sh` |
| 12 | Tmux live status: `⟳` when spinner active | `21_tmux_status_updater.sh` + `24_agent_loop.sh` |

## Tests
15 bats tests in `tests/tui_improvements.bats`

## Key patterns
- Spinner test: `{ kill $PID && wait $PID; } || true` — pipefail + set -e makes wait on killed process return 143
- ctx_bar test: use `run` because `printf %b` with bar chars returns non-zero under set -e
