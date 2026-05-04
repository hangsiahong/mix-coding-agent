# Tools Reference

## 7 Tools (OpenAI function calling)

### bash
- Input: `{"command": "shell command"}`
- Executes via `bash -c`. Self-healing wrapper retries on EACCES (sudo) and not-found (node_modules/npx).
- Risk scored before execution. HIGH needs typed YES. BLOCKED rejected.

### read_file
- Input: `{"path": "/absolute/path"}`
- Returns file contents. Truncated at 10000 chars.
- Returns error if file not found.

### create_file
- Input: `{"path": "/absolute/path", "content": "full content"}`
- Creates file + parent dirs. Fails if file exists (must use edit_file).
- Auto-commits if git enabled.

### edit_file
- Input: `{"path": "/abs/path", "old_text": "exact", "new_text": "replacement"}`
- 4-strategy matching:
  1. **Exact**: direct string replace. Fast path.
  2. **Fuzzy whitespace**: normalizes trailing whitespace + line endings (\r\n→\n, rstrip). Uniqueness checked.
  3. **Fuzzy indent**: strips all leading whitespace per line.
  4. **Block anchor**: matches first+last non-empty lines of old_text, scans file for that pair within range.
- old_text must be unique at whichever strategy succeeds. Multiple matches → error.
- Not found → clear error message.
- Auto-commits if git enabled.

### list_files
- Input: `{"path": "/absolute/dir"}`
- `ls -F` output. Fails if not a directory.

### search_files
- Input: `{"pattern": "regex", "path": "/absolute/dir"}`
- `grep -rn -E -I`. No file extension filtering — searches everything.
- Max 60 matching lines. Empty result returns "(no matches)".

### update_global_memory
- Input: `{"action": "append|replace", "content": "...", "old_text": "..."}`
- Appends/replaces bullets in `~/.mix/memory.md`.
- Persistent cross-project memory.

## Tool Processing Pipeline (22)

Every tool call goes through:
1. Parse tool name + args
2. Display tool icon + target info
3. **Risk scoring** (bash only): score_risk → BLOCKED/HIGH/MED/LOW
4. **User confirmation** (respects AUTO_YES/yolo mode)
5. **Diff preview** (edit_file/create_file): colored unified diff before confirm
6. **Execution**: delegates to run_tool() (13)
7. **Git commit** (if git enabled + success): auto-stage + commit with summary
8. **Test run** (if TEST_CMD set + user confirms): runs test command, appends result
9. **Result display**: first 300 chars, truncated with byte count. Uses `└─` prefix.
10. **History append**: JSON-escaped tool result added to conversation

## Parallel Tool Execution (read-only tools)

`read_file`, `list_files`, `search_files` are classified as read-only and run **concurrently** in background subshells:
- Results written to temp batch directory (`mix-batch-XXXXXX`).
- All parallel results collected after all subshells complete.
- History appended via `append_raw_nosave()` per tool, then **single `save_history` flush** for entire batch.
- Write tools (`bash`, `edit_file`, `create_file`) remain sequential after parallel batch finishes.
- Sequential tools use `silent` flag to skip redundant UI output when part of a multi-tool turn.
