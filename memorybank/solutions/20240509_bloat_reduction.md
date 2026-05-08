# Solution: Bloat Reduction and Bug Fixes

## Problem
- `bash_with_heal` was a duplicate of `bash` but without the actual healing call.
- `spawn_subagent` was defined but not dispatched in `src/22_process_one_tool_call.sh`.
- API payload logic was duplicated between `src/16_api.sh` and `src/18_streaming_api_call.sh`.
- `src/22_process_one_tool_call.sh` was becoming a "mega-file" with giant `case` blocks.

## Solution
1. **API Refactor**: Created `_api_build_payload()` in `src/16_api.sh` to centralize model logic, history filtering, and JSON assembly.
2. **Tool Fixes**: 
    - Updated `src/13_tool_execution.sh` to use `run_with_heal` in `bash_with_heal` case.
    - Wired `spawn_subagent` into the dispatcher.
3. **Modularization**: Moved `bash` and `edit_file` UI/confirmation logic from `src/22_process_one_tool_call.sh` to `src/22a_tool_bash.sh` and `src/22b_tool_edit.sh`.
4. **Dead Code**: Removed `_mix_readlink_f` (redundant with `_mix_realpath`) and `_repo_map_files_unchanged` (unused).

## Verification
- `build.sh` successful.
- `--self-test` passed.
- Subagent successfully spawned and performed analysis.
