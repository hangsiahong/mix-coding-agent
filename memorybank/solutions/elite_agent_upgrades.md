# Solution: Elite Agent Upgrades (Hunks, Ctags, Memory)

## Context
The goal was to move `mix` from a "standard" coding agent to an "Elite" level assistant by adding three high-impact features common in top-tier agents like Aider.

## Problem
1. **Safety**: `edit_file` was all-or-nothing. Small LLM hallucinations in unrelated parts of the file would be committed.
2. **Navigation**: Regex-based repo maps are fast but imprecise for complex languages (C++, Java, Rust).
3. **Retention**: Lessons learned during a task were lost once the context window cleared or history was flushed.

## Solution

### 1. Interactive Hunk Review
- **Mechanism**: Use `python3` to parse a diff into individual hunks. 
- **Interface**: A bash-controlled TTY loop allowing `y` (accept), `n` (reject), `a` (all), `q` (quit).
- **Atomicity**: Changes are applied to a `.next` file first. If reassembly fails (due to hunk rejection causing overlap issues), it warns the user and falls back to the original.

### 2. Ctags-Enhanced Repo Map
- **Detection**: Check for `universal-ctags` (regex-only `ctags` is ignored).
- **Precision**: Uses `--output-format=json` to get exact line numbers and symbol types (functions, classes, variables).
- **Fallback**: Automatically falls back to the fast regex extractor if `ctags` is missing or fails.

### 3. Proactive Memory
- **Trigger**: Hooked into `run_agent()` after a successful final answer.
- **Extraction**: Summarizes what was changed and why.
- **Persistence**: Auto-writes to `memorybank/solutions/` and updates the central log.

## Impact
- **Reduced Regressions**: Users can catch "hallucinated deletions" before they hit disk.
- **Sharper Context**: LLM sees a structured map of definitions, not just a list of files.
- **Compounding Knowledge**: The agent's `memorybank` grows automatically with every fix.

## Lessons Learned
- **TTY Handling**: Reading from `/dev/tty` is essential when the agent's stdin/stdout is redirected (common in subagents/pipes).
- **Hunk Math**: Rejecting a hunk in the middle of a file requires recalculating offsets if using `patch`. Simple line-replacement is safer but less flexible. 
- **JSON for Interop**: Using JSON for `ctags` and session storage prevents the "bash escaping nightmare" when handling complex code symbols.