# Edit Failure Suggestions

## Problem
When `edit_file` fails (`old_text not found` or `not unique`), the LLM wastes 1-2 turns re-reading the file to understand context before retrying.

## Solution
On edit failure, inline Python `suggest_context()` function searches the target file and returns surrounding context directly in the error message.

### Implementation (`src/13_tool_execution.sh`)
- **Not found**: searches for first line of `old_text` in file, shows 5 surrounding lines with line numbers. Falls back to first 5 lines of file.
- **Not unique**: shows all match locations (up to 3) with surrounding lines.
- `[SUGGESTION]` prefix appended to error result.

### Visual indicator (`src/22_process_one_tool_call.sh`)
- Purple `💡 suggestion:` prefix displayed in TUI when result contains `[SUGGESTION]`.

### Key Bug
`suggest_context()` function definition must precede its calls in the inline Python script. Python executes `def` at runtime, not parse time. If defined after calls, `NameError` crashes the suggestion logic silently.

## Impact
- Model self-corrects in 1 turn instead of issuing separate `read_file`.
- Saves ~1 tool call per failed edit, ~2-3 per session with multiple edits.
