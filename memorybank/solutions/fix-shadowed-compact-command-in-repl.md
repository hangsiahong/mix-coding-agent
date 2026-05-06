# Task: Fix shadowed compact command in REPL
Date: 2024-05-18

## Result
The `/compact` command wasn't working. It was silently doing nothing. There were duplicate case branches for `/compact` and `/undo` in `src/25_repl_commands.sh`. The first `/compact` branch did not override `MAX_HIST_MSGS` to 0, which meant `compact_history` silently returned because the history length was below the threshold. The second branch (which properly set `MAX_HIST_MSGS=0`) was unreachable. Removed the duplicate `/compact` and `/undo` branches.

## Files Modified
- `src/25_repl_commands.sh`