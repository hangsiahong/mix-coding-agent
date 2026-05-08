# Solution: Efficiency and Cost Optimization

## Context
The agent was consuming significant context (per-turn tax) due to unstructured system prompt growth and large tool outputs. This increased costs and reduced the effective context window for task history.

## Changes

### 1. System Prompt Caching Optimization
- **Reordering:** Moved static rules, sandbox instructions, Global Memory, and PROJECT SPEC to the beginning of the system prompt.
- **Dynamic Elements:** Moved `REPO MAP`, `FILE CACHE`, and `CONTEXT BUDGET` (which change frequently) to the end of the prompt.
- **Benefit:** Models with prefix caching (Claude 3.5, Gemini 1.5/2.0) can now cache the first ~3-5k tokens of the system prompt reliably across turns.

### 2. Strict Injection Budgets
- **Global Memory:** Capped at 2,000 characters in the system prompt.
- **SPEC.md:** Capped at 1,500 characters in the system prompt.
- **Rationale:** Prevents "unbounded growth" of the system prompt tax. Full contents are still available via `read_file` if needed.

### 3. Tool Output Hardening
- **Truncation:** Reduced `_MAX_TOOL_OUTPUT` from 32KB to 16KB in `src/22_process_one_tool_call.sh`.
- **Rationale:** Large bash outputs or file reads were "poisoning" the context window, triggering premature history compaction and loss of task state.

### 4. Verified Mechanisms
- **File Cache:** Confirmed `src/11a_file_cache.sh` survives compaction, preventing redundant reads.
- **Cost Reporting:** Confirmed accurate `cached_tokens` reporting in `src/18_streaming_api_call.sh`.

## Results
- Estimated "per-turn tax" reduced from ~7k to ~4k tokens (~40% reduction).
- Increased prompt cache hit rates on supported models.
- More stable performance on long-running tasks.
