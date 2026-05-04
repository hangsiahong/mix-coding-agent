# SPEC: /resume — Session Context Recovery

## §G Goal
Save session state on exit and restore it on next startup via `/resume`, eliminating 2-3 re-orientation turns per session. The model "remembers" file cache, env info, repo map, skills, and recent task context.

## §C Constraints
- No external deps — bash + python3 (already required)
- Session file: `.agent/session.json` in WORKDIR (gitignored)
- Must not break piped/non-interactive mode
- Must not leak API keys into session file
- Session file < 50KB (truncate file cache if needed)
- Backward compatible: missing/corrupt session = silent skip

## §I Interfaces
### New file: `src/11c_session.sh`
- `session_save()` — called in EXIT trap and before REPL prompt
- `session_load()` — called once at startup, before first prompt
- `session_clear()` — called by `/flush` (already clears history)

### Session file schema (`.agent/session.json`)
```json
{
  "version": 1,
  "timestamp": 1714800000,
  "env_info": "git:master node shellcheck",
  "git_enabled": true,
  "git_branch": "master",
  "provider": "default",
  "model": "glm-5",
  "base_url": "https://ai.koompi.cloud/v1",
  "caveman_mode": "full",
  "agent_mode": "fast",
  "auto_yes": false,
  "active_skills": "",
  "file_cache": {"/path/to/file": {"content":"...","mtime":123,"atime":456,"lines":42}},
  "file_cache_order": "/path1 /path2",
  "repo_map": "...",
  "repo_map_mtimes": "file:mtime:...",
  "repo_map_time": 1714800000,
  "last_input": "fix the bug in auth",
  "cwd": "/home/user/project"
}
```

### REPL command
- `/resume` — load saved session, restore file cache + repo map + env info + config
- Auto-prompt on startup: "Previous session found (2h ago). /resume to restore."

## §V Invariants
- Session file never contains API_KEY or KCONSOLE_API_KEY
- session_load() validates JSON before applying; corrupt = warn + skip
- file_cache entries validated (mtime check) before use after restore
- repo_map TTL still enforced (10min) — stale maps rebuilt
- `/flush` also clears session file
- CWD must match (or subdirectory) — don't restore wrong project's context

## §T Tasks
1. [x] Create `src/11c_session.sh` with session_save, session_load, session_clear
2. [x] Add `session_load()` call to startup (in src/07_environment_detection.sh)
3. [x] Add `session_save()` to EXIT trap in src/27_main_repl.sh
4. [x] Add `/resume` command to src/25_repl_commands.sh
5. [x] Startup message: "Previous session (Xh ago). /resume to restore."
6. [x] Add `.agent/` to .gitignore
7. [x] Add bats tests for session functions (27 tests)
8. [x] Update build.sh to include new file
9. [x] Rebuild and verify

## §B Bugs (found during implementation)
- None yet
