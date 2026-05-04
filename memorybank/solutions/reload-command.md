# /reload Command

**Date:** 2025-07-14
**Files:** `src/25_repl_commands.sh`, `src/27_main_repl.sh`

## What
`/reload` — rebuild mix from source and restart, preserving session context.

## Flow
1. Find project root (dir with `build.sh` + `src/`)
2. Run `bash build.sh`
3. Copy compiled binary to install location
4. `session_save` + `save_history`
5. `exec "$_reload_bin"` — replaces process with new binary
6. New process runs `session_load` on startup → context restored

## Design decisions
- Uses `exec` to replace process — clean, no orphan processes
- Session persistence is the key enabler (already existed for `/resume`)
- Falls back to `./mix` if install location not writable
- Build failures show last 10 lines of output

## Also added in this session
- **Prompt history (Up/Down arrows):** readline HISTFILE=`~/.mix/input_history`, `history -s` after each read, `history -a` to persist. 500 entries, deduplicated.
