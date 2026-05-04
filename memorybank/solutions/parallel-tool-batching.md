# Parallel Tool Batching

## Problem
Agent was slow on multi-read turns. Each `read_file`, `list_files`, `search_files` call blocked sequentially. Each tool also triggered a separate `save_history` disk write.

## Solution (commit f8565f1 + 4442b40)

### Parallel Execution
- Read-only tools (`read_file`, `list_files`, `search_files`) classified and dispatched to background subshells (`&`).
- Results written to temp batch directory (`mktemp -d -t mix-batch-XXXXXX`).
- Main process waits for all subshells to complete before collecting results.

### Batch History Flush
- `append_raw_nosave()` added to `src/12_auto_compact_history.sh` — appends tool result to in-memory HISTORY without disk write.
- After all parallel results collected, single `save_history` call flushes entire batch.
- Reduces N disk writes to 1 per parallel batch.

### TUI De-duplication
- Sequential tools that follow parallel batch use `silent` flag to skip redundant result display.
- `└─` prefix standardized across both parallel and sequential result summaries.

### edit_file 4th Strategy: Anchor Match
- Added block-anchor matching as 4th fallback: matches first+last non-empty lines, scans for unique pair.
- Helps when LLM-generated old_text has internal whitespace drift but correct boundaries.

## Files
- `src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh` — orchestration, parallel/sequential split
- `src/12_auto_compact_history.sh` — append_raw_nosave()
- `src/13_tool_execution.sh` — 4-strategy edit_file
- `src/22_process_one_tool_call.sh` — silent flag dispatch
- `src/01_config.sh` — MAX_TURNS=100
