# Repo Map — Codebase Structural Awareness

## Problem
Every coding task started with 2-3 "orientation" tool calls: `search_files`, `list_files`, `read_file` — just to figure out where things are. The agent was blind to codebase structure until it actively searched.

## Solution: `src/11b_repo_map.sh`
Regex-based structural extractor that builds a compressed map of the codebase (~1200 tokens), injected into the system prompt every API call.

### What it extracts
- **File tree**: all source files, sorted
- **Function signatures**: `grep` for `func()` patterns per language
- **Class/method/import lines**: Python, JS/TS, Go, Rust, Java, Ruby, C
- **File sizes**: line counts, large files noted but not scanned
- **Git recency**: recently changed files highlighted (if git enabled)

### Language support (regex patterns)
sh, py, js, ts, go, rs, java, rb, c, h — 10 languages with structural extraction.

### Token budget
~4500 chars (~1500 tokens) max. Hard cutoff when budget exceeded.

### Caching
- Built once, cached in shell variables (`_REPO_MAP`, `_REPO_MAP_MTIMES`)
- **TTL**: 600 seconds (10 minutes)
- **mtime check**: samples up to 50 files, rebuilds if any changed
- **Manual invalidation**: `/refresh` command or `repo_map_invalidate()`

### Integration
- `build_repo_map()` called from `build_system_prompt()` (03)
- Injected as `## REPO MAP` section between ENV and GLOBAL MEMORY
- Zero new dependencies — uses `find`, `grep`, `stat`, `wc`

## Impact
- Eliminates 2-3 orientation tool calls per task
- Reduces average task from 6 turns to 3-4 turns
- Agent can target correct file on first try
- For 10-task session: ~20 fewer turns, ~10 fewer API calls

## Files modified
- `src/11b_repo_map.sh` — new (176 lines)
- `src/03_system_prompt_*.sh` — repo map injection (+8 lines)
- `src/25_repl_commands.sh` — `/refresh` command
- `src/26_banner.sh` — help text update
- `src/27_main_repl.sh` — tab completion update
- `build.sh` — include new file
