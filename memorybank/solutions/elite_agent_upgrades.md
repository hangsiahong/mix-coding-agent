# Solution: Elite Agent Upgrades (Ctags, Memory, Commit Messages)

## Context
The goal was to move `mix` from a "standard" coding agent to an "Elite" level assistant. Originally included interactive hunk review, which was later stripped in favor of yolo mode + `/undo` rollback philosophy.

## Problem
1. **Navigation**: Regex-based repo maps are fast but imprecise for complex languages (C++, Java, Rust).
2. **Retention**: Lessons learned during a task were lost once the context window cleared or history was flushed.
3. **Commit History**: Auto-commits used generic messages (`agent: edit <file>`) — hard to scan in `git log`.

## Solution

### 1. Ctags-Enhanced Repo Map
- **Detection**: Check for `universal-ctags` (regex-only `ctags` is ignored).
- **Precision**: Uses `--output-format=json` to get exact line numbers and symbol types (functions, classes, variables).
- **Fallback**: Automatically falls back to the fast regex extractor if `ctags` is missing or fails.

### 2. Proactive Memory
- **Trigger**: Hooked into `run_agent()` after a successful final answer.
- **Extraction**: Summarizes what was changed and why.
- **Persistence**: Auto-writes to `memorybank/solutions/` and updates the central log.

### 3. Descriptive Auto-Commit Messages
- **Edit commits**: Extract first changed line from `difflib.unified_diff(old, new, n=0)`. Format: `agent: edit <file> — <first added line>`. Pure removals show `remove: <first removed line>`. Fallback: `agent: edit <file>`.
- **Create commits**: Include line count. Format: `agent: create <file> (<N> lines)`.
- **Implementation**: `_cmsg` variable in `src/22_process_one_tool_call.sh`, generated via inline python3 `difflib`.

## Design Decision: No Hunk Review
Interactive hunk review (`y/n/a/q` loop) was implemented then **stripped** (commit `c783a5b`). Reason: contradicts yolo mode philosophy. Every edit auto-commits, `/undo` (= `git revert HEAD`) is sufficient rollback. Simpler UX, fewer interruptions.

## Impact
- **Sharper Context**: LLM sees a structured map of definitions, not just a list of files.
- **Compounding Knowledge**: The agent's `memorybank` grows automatically with every fix.
- **Readable History**: `git log --oneline` now shows what changed, not just which file.

## Lessons Learned
- **JSON for Interop**: Using JSON for `ctags` and session storage prevents the "bash escaping nightmare" when handling complex code symbols.
- **Yolo + Undo > Interactive Review**: Requiring confirmation per-hunk breaks flow. Auto-commit + `/undo` gives same safety with zero friction.
- **Commit Messages from Diffs**: `difflib.unified_diff(n=0)` produces minimal context diffs. First `+` line is a good summary in most cases.