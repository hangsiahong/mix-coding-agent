# set -u Session Hardening Fix

## Problem
Agent exited immediately after provider activation in interactive mode. Root cause: `set -u` (nounset) in `src/00_header.sh` caused fatal crash when `EXIT` trap called `session_save()` during early process termination (e.g., `exec tmux` handoff in `02_tmux_bootstrap.sh`) before `src/11a_file_cache.sh` and `src/11b_repo_map.sh` were sourced.

## Timeline
1. `00_header.sh` sets `set -uo pipefail`
2. `01_config.sh` runs (INTERACTIVE set here now)
3. `02_tmux_bootstrap.sh` does `exec tmux ...` — triggers EXIT trap on parent process
4. EXIT trap calls `session_save()` which references `$_FILE_CACHE`, `$_REPO_MAP`, etc.
5. These vars not yet defined → `set -u` kills process

## Fixes Applied

### 1. Early INTERACTIVE detection (`src/01_config.sh`)
Moved `[ -t 0 ]` check from `src/27_main_repl.sh` to `src/01_config.sh`. All components (session, banner, providers) now know terminal state from startup.

### 2. Safe defaults in `src/11c_session.sh`
Added default initializations at top of file:
```bash
_FILE_CACHE="${_FILE_CACHE:-}"
_FILE_CACHE_ORDER="${_FILE_CACHE_ORDER:-}"
_REPO_MAP="${_REPO_MAP:-}"
_REPO_MAP_MTIMES="${_REPO_MAP_MTIMES:-}"
_REPO_MAP_TIME="${_REPO_MAP_TIME:-0}"
_LAST_INPUT="${_LAST_INPUT:-}"
```

### 3. REPL guard (`src/27_main_repl.sh`)
Replaced hard `INTERACTIVE` detection with `if [ -z "${INTERACTIVE:-}" ]` — won't overwrite value from `01_config.sh`.

### 4. `_skill_status` init
Added `_skill_status=""` before REPL loop to prevent `set -u` violation in prompt rendering.

## Lesson
With `set -u`, any variable referenced in EXIT trap handlers **must** have defaults set **before** the trap is installed, because early exits (exec, signals, errors) can trigger the trap before normal initialization completes.
