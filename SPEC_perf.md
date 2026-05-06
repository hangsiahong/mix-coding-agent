# SPEC: Performance Optimization — Prompt-to-LLM Latency

## §G Goal
Reduce the delay between user pressing Enter and the first API token arriving. Two targets:
1. **Local pre-processing** (bash/python overhead before curl fires) — currently ~200-500ms wasted
2. **Token efficiency** (smaller payloads = faster TTFT from API) — currently sending ~3000-5000 excess tokens

## §C Constraints
- No behavior changes — same features, same output
- No new dependencies
- Must work in both interactive and piped mode
- Must not break session/compact/cache correctness

## §I Interfaces
Modified files only, no new interfaces.

## §V Invariants
- System prompt content unchanged (same info, tighter packing)
- Repo map same structure, just cached properly
- compact_history gate unchanged (still respects MAX_HIST_MSGS)
- Token usage tracking still works

## §T Tasks
1. [x] Profile hot path: Enter → API call
2. [x] Cache system prompt (avoid rebuild every call)
3. [x] Defer repo map validation (stat() calls are expensive)
4. [x] Skip compact_history count on every call (use cheap counter)
5. [x] Reduce python3 subprocess calls in hot path
6. [x] Compress system prompt (remove redundant sections when inactive)
7. [x] Add timing instrumentation (/stats shows pre-process latency)

## §B Bugs
1. **FIXED**: sysprompt cache used bash variables but `build_system_prompt()` runs in subshell via pipe — variable changes lost. Fixed with file-based cache (`/tmp/mix-sysprompt-cache-$$` + dirty flag file).
