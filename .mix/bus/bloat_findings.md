# Bloat and Redundancy Findings

## 1. API Logic Duplication
- **Files**: `src/16_api.sh` and `src/18_streaming_api_call.sh`.
- **Redundancy**: Both functions (`call_api` and `call_api_stream`) contain identical code for:
    - Model prefixing (`_GOOGLE_VERTEX_MODEL_PREFIX`).
    - History filtering (`_apply_provider_history_filter`).
    - Extra payload JSON generation (`${PROVIDER}_extra_payload_json`).
    - Assembling the final JSON payload using a Python one-liner.
- **Impact**: Changes to API payload structure must be made in two places.
- **Recommendation**: Extract shared logic into `_api_build_payload()` in `src/16_api.sh`.

## 2. Giant Dispatchers
- **Files**: `src/25_repl_commands.sh` (REPL commands) and `src/13_tool_execution.sh` / `src/22_process_one_tool_call.sh` (Tool execution).
- **Redundancy**: These files use massive `case` statements. Many commands/tools (like `edit_file`, `bash`, `/provider`) have 50+ lines of logic embedded directly in the dispatcher.
- **Impact**: High cognitive load, difficult to navigate, and prone to merge conflicts.
- **Recommendation**: Modularize tools and commands. Move large tool implementations to `src/tools/` and large REPL commands to `src/repl/`.

## 3. Broken/Duplicate Logic: `bash_with_heal`
- **File**: `src/13_tool_execution.sh`.
- **Issue**: The `bash_with_heal` case in `run_tool` is almost a verbatim copy of the `bash` case but it **fails to actually call `run_with_heal`**. It just runs `bash -c "$cmd"`.
- **Impact**: The self-healing feature is bypasssed.
- **Recommendation**: Refactor `run_tool` to have `bash` and `bash_with_heal` share logic, with a flag to toggle healing.

## 4. Performance: JSON Parsing Overhead
- **Issue**: Every tool call and many REPL commands use `python3 -c 'import json; ...'` to extract single values from JSON strings.
- **Impact**: Slows down execution, especially in loops, due to Python startup time.
- **Recommendation**: Consider a lightweight JSON parser if available, or pass arguments differently (e.g., as env vars) when possible to minimize Python calls.

## 5. Dead Code
- **Functions**:
    - `_mix_readlink_f` (replaced by `_mix_realpath`?).
    - `pulse_save` (defined in `src/11c_session.sh` but not called).
    - `run_with_heal` (defined in `src/08_self_healing_bash_wrapper.sh` but not used correctly).
    - Various provider hooks (`copilot_*`, `google_*`) when the provider is not active.

## 6. Miscellaneous
- `src/00a_compat.sh` has `_mix_readlink_f` which is unused.
- `src/11b_repo_map.sh` has `_repo_map_files_unchanged` which is unused.
