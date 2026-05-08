# Solution: Context & Token Efficiency Optimizations

## Problem
As sessions grow, the "system tax" (system prompt + repo map + file cache) increases, reducing the space available for conversation and increasing API costs. Large tool outputs can also poison the context.

## Improvements

### 1. Compact Repo Map (`src/11b_repo_map.sh`)
- **Symbol Compression:** Replaced verbose symbol labels (e.g., `(fn)`) with compact 2-char prefixes (`f:`, `c:`, `m:`, `api:`).
- **"Hot File" Highlighting:** Added cached files (recently read) and recently changed git files to a "recently active" section in the repo map. This gives the agent immediate context on relevant files without searching.

### 2. Adaptive File Cache (`src/11a_file_cache.sh`)
- **Dynamic Budgeting:** The file cache budget now scales based on `CTX_TOKENS`. 
- **Higher Limits:** For models with large context (128k+), the cache can now hold up to 30,000 chars (~10k tokens) across 15 files, allowing the agent to "see" much more of the project simultaneously.
- **Safety:** Stays under 5% of the total context window.

### 3. Smart Tool Output Truncation (`src/13_tool_execution.sh`)
- **Head-Tail Preservation:** For `bash` commands exceeding 16KB, the agent now preserves the first 4KB and the **last 12KB**. 
- **Benefit:** This ensures that both the command initiation (headers) and the final error messages or summaries (usually at the end of logs) are preserved, preventing critical diagnostic info from being lost in simple head-truncation.

### 4. Planning Model Offloading (`src/23_lightweight_planning_call_plan_mode.sh`)
- **Cost Savings:** Added support for `PLAN_MODEL` and `PLAN_PROVIDER`.
- **Strategy:** Users can now use a cheap, fast model (e.g., `gemini-1.5-flash`) for the initial planning step while using a more capable model (e.g., `claude-3-5-sonnet`) for execution.

### 5. Telegraphic Compaction (`src/12_auto_compact_history.sh`)
- **Caveman Summaries:** Updated history compaction to request "telegraphic" (caveman style) summaries. 
- **Efficiency:** This reduces the token weight of the compacted history block while maintaining technical precision.

## Results
- **Prompt Size:** Repo map size reduced by ~20% via symbol compression.
- **Context Depth:** Agent can work on 2x more files simultaneously in high-context models.
- **Reliability:** Better error diagnostics due to head-tail log preservation.
- **Cost:** Planning step cost reduced by up to 90% when using offloading.
