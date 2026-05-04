# Codebase Audit — mix coding agent (2025-05)

Original audit of ~1520 lines. **Most critical/medium issues resolved in subsequent development.** This page preserved for historical reference.

## Status Summary

| Category | Total | Resolved | Remaining |
|---|---|---|---|
| Critical Security (S) | 4 | 4 | 0 |
| Correctness Bugs (B) | 7 | 5 | 2 (minor) |
| Robustness (R) | 7 | 5 | 2 (known) |
| Architecture (A) | 6 | 3 | 3 (by design) |

## Resolved Issues

### S1: eval → bash -c ✅
All command execution uses `bash -c "$cmd"` in both 13_tool_execution.sh and 08_self_healing.

### S2: API key redaction ✅
`save_history()` in 11_history.sh sed-replaces KCONSOLE_API_KEY before writing.

### S3: Safe sudo ✅
08_self_healing shows full command + explicit `[y/N]` confirmation before sudo.

### S4: Trusted rc only ✅
04_project_local_extensions only sources ~/.mix/rc.sh. Project .agent/rc.sh removed.

### B1: edit_file return ✅
`#return` commented out in 13. Result flows through correctly.

### B2: JSON append ✅
append_raw in 12 uses python3 stdin pipe. No bash string manipulation.

### B3: Compact consistency ✅
Compact now handles provider keys + extra headers like streaming does.

### B4: search_files extensions ✅
No --include flags. Raw grep on all files.

### R1: EXIT trap ✅
27_main_repl has `trap stop_spinner; rm -f /tmp/mix-* EXIT TERM HUP`.

### R4: ARG_MAX ✅
append_raw passes history via stdin pipe to python3.

### A1: Tool dispatch ✅
22 delegates to run_tool(). 22 handles UX, 13 handles execution.

### B7: FAIL_STREAK ✅
create_file decline preserves streak.

## Remaining (Known, Acceptable)

- **B6**: Plan mode phantom message (minor, rarely noticed)
- **A4**: Skill files inline in system prompt (by design, user-controlled)
- **A6**: Zero tests (nice-to-have)
- **S5/S6**: Regex-based risk scoring inherent limitations (documented)

## Codebase Now
2735 lines across 29 source files + 1 provider. See memorybank/pages/architecture.md for current component map.
