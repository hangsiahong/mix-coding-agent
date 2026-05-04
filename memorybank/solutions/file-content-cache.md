# File Content Cache

## Problem
Every time the model needs to read a file, it spends a full turn (API call → tool → result → next API call). After history compaction, file contents are lost and must be re-read. A typical 10-task session wastes 15-20 turns on re-reading files the agent already saw.

## Solution
Session-scoped file content cache that survives history compaction. Injected into system prompt alongside repo map.

### Architecture
- `_FILE_CACHE`: JSON dict `{path: {content, mtime, atime, lines}}`
- `_FILE_CACHE_ORDER`: space-separated access order (most recent last)
- `file_cache_put()`: adds/updates file in cache, moves to end of access order
- `file_cache_del()`: removes file from cache
- `file_cache_validate()`: removes stale entries (deleted files, externally modified)
- `build_file_context()`: builds markdown section for system prompt, top 8 files, 3000 char budget

### Integration Points
1. **`read_file`** (13_tool_execution.sh): auto-caches on every read
2. **`edit_file`** (13_tool_execution.sh): auto-updates cache after successful edit
3. **`create_file`** (13_tool_execution.sh): auto-caches newly created files
4. **System prompt** (03_system_prompt.sh): injects `## CACHED FILES` section after repo map
5. **REPL**: `/cache` shows cached files, `/cache clear` empties cache

### Budget
- 3000 chars (~1000 tokens) in system prompt
- Max 8 files, 400 chars per file
- Files truncated with head/tail preservation
- Lives alongside repo map (4800 chars) — total ~7800 chars for context

### Key Design Decisions
- **argv-based python3 calls** — avoids stdin/ARG_MAX issues with multiline content
- **Temp file for content** — file content passed via temp file, not stdin
- **Mtime validation** — cache invalidates when file modified externally
- **Access order tracking** — most recently accessed files shown first
- **Survives compaction** — cache is separate from HISTORY, not affected by LLM summarization

## Impact
- Eliminates re-reading files after compaction
- Model can reference previously-read files on turn 1
- Saves 2-5 turns per "return to task after compaction" scenario

## Files Changed
- `src/11a_file_cache.sh` (new, ~130 lines)
- `src/13_tool_execution.sh` (+3 cache hooks)
- `src/03_system_prompt_*.sh` (+6 lines injection)
- `src/25_repl_commands.sh` (+14 lines /cache command)
- `src/27_main_repl.sh` (+1 autocomplete entry)
- `build.sh` (+1 source line)
