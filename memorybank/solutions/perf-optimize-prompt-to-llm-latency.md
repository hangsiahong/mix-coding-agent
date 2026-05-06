# Perf: Optimize Prompt-to-LLM Latency
Date: 2024-05-18

## Problem
Sluggish feel between pressing Enter and first API token arriving. Root cause: multiple expensive operations in the hot path (Enter → curl).

## Hot Path Analysis
Every API call triggered:
1. `compact_history` → python3 subprocess to count messages (~50ms)
2. `append_text` → python3 to escape + append (~20ms)
3. `build_system_prompt` → rebuilds from scratch every call:
   - `build_repo_map` → `stat()` on up to 50 files (~100ms)
   - `build_file_context` → `file_cache_validate` python3 + stat() (~50ms)
   - `cat ~/.mix/memory.md` → file read
4. Payload build → python3 for JSON assembly (~30ms)
5. Total local pre-processing: ~200-500ms wasted before curl fires

## Fixes Applied
1. **System prompt caching**: `_SYSPROMPT_CACHE` + `_SYSPROMPT_DIRTY` flag. Rebuilds only when state changes (edit, compact, mode switch, /refresh).
2. **Repo map: pure TTL cache**: Removed `_repo_map_files_unchanged()` stat() checks within TTL window (10min).
3. **File cache validation throttled**: Only re-validates cached files every 30s instead of every API call.
4. **Compact history fast path**: `grep -c '"role"'` instead of `python3 -c 'json.load...len()'` to count messages.
5. **History filter fast path**: Skip python3 thought_signature stripping when bash `case` shows no such fields in history string.
6. **Pre-process timing**: Shows ms when >50ms so user can see the improvement.

## Estimated Impact
- **Before**: ~250-500ms local pre-processing per turn (after first turn)
- **After (cached path)**: ~30-80ms local pre-processing (just append_text + payload build + curl)
- **Savings**: ~200-400ms per turn, most noticeable on multi-turn tool loops

## Token Efficiency
Current system prompt token budget:
- Base prompt: ~500 tokens (necessary)
- Repo map: ~1600 tokens (already budget-capped at 4800 chars)
- File cache: ~1000 tokens (already budget-capped at 3000 chars)
- Global memory: ~670 tokens (capped at 2000 chars)
- SPEC.md: ~500 tokens (capped at 1500 chars)
- Tools JSON: ~1000 tokens (necessary, benefits from prompt caching)
- Total: ~5300 tokens in system prompt — reasonable

Further token compression would need API-level prompt caching (Anthropic/GPT-4o support this, koompi proxy may or may not pass it through).

## Files Modified
- `src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh` — cache + invalidation
- `src/11a_file_cache.sh` — validation throttling
- `src/11b_repo_map.sh` — pure TTL cache
- `src/11_history.sh` — fast path for history filter
- `src/12_auto_compact_history.sh` — cheap message counting
- `src/13_tool_execution.sh` — sysprompt invalidation hooks
- `src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh` — timing instrumentation
- `src/25_repl_commands.sh` — invalidation on mode/provider changes, /stats improvements
