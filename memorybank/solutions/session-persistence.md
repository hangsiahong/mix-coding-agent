# Session Persistence (/resume)

## What
Save session state on exit, restore on next startup via `/resume`. Eliminates 2-3 re-orientation turns per session.

## Files
- `src/11c_session.sh` (232 lines) — session_save, session_load, session_apply, session_clear

## Schema
`.agent/session.json` — version, timestamp, env_info, git info, provider/model config, caveman/mode/yoyo state, file cache, repo map, last input, cwd.

## Key Design
- **Base64 encoding** for shell/python data exchange. Never pass structured data through $() — use temp file + source pattern.
- Session file never contains API_KEY or KCONSOLE_API_KEY
- session_load() validates JSON before applying; corrupt = warn + skip
- File cache entries validated (mtime check) after restore
- repo_map TTL still enforced (10min)
- CWD must match (or subdirectory) — don't restore wrong project's context
- `/flush` also clears session file
- **Overwrite Protection**: `session_save` skips if a session is waiting to be resumed and no new turn has been taken, preventing accidental deletion of a saved session on a fresh startup.

## Tests
28 bats tests in `tests/session.bats`
