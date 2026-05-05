# Mid-Loop Auto-Compact

## Problem
`compact_history` only called once — at top of `run_agent()`, before user message appended. During multi-turn tool-use loop (up to `MAX_TURNS=100`), history grew unbounded. Heavy sessions (20+ tool calls = 60+ messages) could exceed context window mid-loop.

## Root Cause
`src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh` — the while loop iterates `turn 1..MAX_TURNS` making API calls and appending tool results, but never checked if history exceeded `MAX_HIST_MSGS`.

## Fix
Added `compact_history` call at top of while loop (after turn > 1):
```bash
[ "$turn" -gt 1 ] && compact_history
```

## Why Safe
- `compact_history` has cheap count gate: `[ "$count" -lt "$MAX_HIST_MSGS" ] && return`
- Real API call to summarize only fires when threshold hit (default 60 messages)
- JSON count via python3 is ~1ms per turn — negligible overhead
- Turn 1 skipped because `run_agent()` entry already compacted
- Keeps last 10 messages verbatim — recent tool results never lost

## Files Changed
- `src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh` — 3 lines added

## Tests
184/184 passing. No new tests needed (existing compact_history tests cover the function).
