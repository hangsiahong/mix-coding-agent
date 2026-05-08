# Solution: Pulse Context Recovery Fix

## Problem
The "Pulse" feature (lightweight context summary that survives `/flush`) was not appearing in the agent's system prompt despite the code existing.

## Root Causes
1. **Relative Paths**: `_PULSE_FILE` was set to `.agent/pulse.json`. Depending on the execution context of the system prompt builder, this relative path might not resolve correctly.
2. **Python Syntax Error**: The `pulse_load` function used a `python3 -c` command with an f-string that contained an unquoted key or incorrectly escaped quotes, leading to a `NameError` or `SyntaxError`.
3. **Cache Invalidation**: `pulse_save` did not invalidate the system prompt cache, meaning updates to the pulse wouldn't be seen until another event (like an edit) triggered a rebuild.

## Fixes
1. **Absolute Paths**: Changed `_PULSE_FILE` and `_SESSION_FILE` to use `$WORKDIR`.
2. **Robust Python Script**: Refactored the `pulse_load` python script to use separate variables and avoid complex f-string expressions that are sensitive to shell quoting.
3. **Proactive Invalidation**: Added `_sysprompt_invalidate` to `pulse_save`.

## Verification
Running `build_system_prompt` now correctly shows the `[LAST SESSION PULSE]` block in the output.
