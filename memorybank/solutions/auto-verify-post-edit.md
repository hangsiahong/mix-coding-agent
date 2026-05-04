# Auto-Verify (Post-Edit Verification)

**Date**: 2025-07-13
**File**: `src/13a_auto_verify.sh` (195 lines)
**Impact**: Eliminates silent syntax/type errors — catches them immediately after edit

## Problem
After `edit_file` or `create_file`, the model had no way to know if changes introduced syntax errors. It would move on, compound bugs, and only discover errors turns later when something breaks.

## Solution
Auto-run verification after every successful file modification:
1. **Syntax check** — file-type specific, instant (bash -n, python py_compile, node --check)
2. **Lint** — if available (shellcheck, ruff, eslint)
3. **Typecheck** — if configured (mypy, tsc --noEmit, cargo check)
4. **Tests** — if TEST_CMD detected and file is not a test file

## Language Support
- **Shell**: bash -n, shellcheck
- **Python**: py_compile, ruff, mypy
- **JS/TS**: node --check, eslint, tsc --noEmit
- **Rust**: cargo check
- **Go**: go vet, go build
- **Ruby**: ruby -c
- **Java**: javac
- **C/C++**: g++/clang++ -fsyntax-only

## Design Decisions
- **Silent on success** — no output if all checks pass (avoids context bloat)
- **Detailed on failure** — shows error lines + exit codes
- **Graceful degradation** — only runs tools that are installed
- **Timeout** — 15s per check, 60s for tests, 30s for cargo
- **Test heuristic** — skips test run for files matching *test*/*spec*

## Integration Points
- `src/13_tool_execution.sh`: hooks after edit_file (line ~116) and create_file (line ~145)
- `src/22_process_one_tool_call.sh`: visual indicator for verify results
- `src/03_system_prompt_*.sh`: model instructed to fix verify failures
- `src/07_environment_detection.sh`: detects shellcheck/ruff/mypy availability

## REPL
- `/verify` — show status
- `/verify on|off` — toggle
- `AUTO_VERIFY=off` env var to disable

## Key Bug Fixed
`_cmd="${line#*|}"` stripped only first `|` in CHECK lines, leaving label in command.
Fix: `_cmd="${line#CHECK|${_label}|}"` — strips full known prefix.

Also: `$'\n'` for newlines (not `"\n"` which is literal in bash).
