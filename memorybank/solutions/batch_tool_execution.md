# Solution: Batch Tool Execution & Turn Optimization

## Context
The agent often performed related tasks (e.g., editing 3 files) over multiple API turns, leading to high latency and unnecessary costs. Additionally, multi-tool turns required repetitive user confirmations.

## Changes

### 1. System Prompt Guidance
- **Encouragement:** Updated the system prompt to explicitly instruct the agent to bundle multiple tool calls in one turn.
- **Parallelization Hint:** Informed the agent that `read_file`, `list_files`, and `search_files` are parallelized, encouraging it to read multiple files at once.

### 2. Batch Execution Engine
- **Sequential Context:** Modified the agent loop to track sequential tool batches (bash, edit, create).
- **Progress Indicators:** The UI now shows `[1/3]` style progress indicators for sequential tools.
- **Fail-Fast Batching:** If a tool in a batch fails (e.g., a bash command returns an error or the user declines an edit), the remaining tools in that turn's batch are aborted to prevent cascading failures.

### 3. Batch Confirmation ("Apply All")
- **Batch Auto-Yes:** Introduced a `[Y/n/a]` prompt for sequential tools.
- **"a" (All):** Selecting `a` enables `_BATCH_AUTO_YES` for the remainder of the current turn's batch, auto-applying all remaining edits or MED-risk bash commands.
- **Scope:** This auto-approval only persists for the duration of the current turn, maintaining safety for future turns.

### 4. Smart Test Suppression
- **Logic:** `TEST_CMD` (auto-verify) is now only offered after the *last* tool in a batch.
- **Benefit:** If an agent edits 4 files, the user is only prompted to run tests once at the end, rather than 4 times.

## Results
- **Turn Savings:** Significant reduction in turns for multi-file edits and multi-file reads.
- **UX Improvement:** "Apply All" reduces confirmation fatigue while maintaining the safety of reviewing the first few changes in a batch.
- **Reliability:** Aborting on failure prevents the agent from attempting dependent changes when a prerequisite has failed.
