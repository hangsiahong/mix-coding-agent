# Smart Bash Output Truncation

## Problem
Large bash outputs (build logs, test suites) truncated with simple head/tail lose error context from the middle section. LLM cannot diagnose failures when errors are in truncated part.

## Solution
Changed from 100/100 head+tail to **50/50** with error extraction from truncated middle.

### Implementation (`src/08_self_healing_bash_wrapper.sh`)
- **Threshold**: 200 total lines triggers truncation.
- **Split**: 50 lines head + 50 lines tail.
- **Error extraction**: `grep -iE '(error|fail|warn|exception|fatal|traceback)'` from truncated middle section, capped at 20 lines.
- **Format**: `[KEY ERRORS from truncated section]` section between head and tail.

### Key Bug
Original version reassigned `$out` to head part, then tried to `tail` from already-modified variable. Fixed by saving `_tail_part` before reassignment.

## Impact
- Diagnostic signal preserved even for multi-hundred-line outputs.
- LLM can see errors without re-running command or reading log files.
