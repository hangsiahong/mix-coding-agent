# SPEC: Versioning + Self-Heal System

## §G Goal
When a new feature breaks mix startup, automatically fall back to last working version and offer self-repair. No more manual `git revert` or broken sessions.

## §C Constraints
- Wrapper script must be ~30 lines, zero dependencies, **never breaks**
- Versioned binaries stored in `~/.mix/versions/`
- Keep last 5 versions, auto-prune older ones
- Session preserved across fallback (session_save/load already works)

## §I Interfaces

### Wrapper: `~/.local/bin/mix` (the installed entry point)
```bash
#!/bin/bash
MIX_DIR="$HOME/.mix/versions"
CURRENT="$MIX_DIR/current"
LAST_GOOD="$MIX_DIR/last_good"
CRASH_LOG="/tmp/mix-crash.log"

# Try current version with 3-second health check
timeout 3 bash "$CURRENT" --self-test 2>"$CRASH_LOG"
if [ $? -ne 0 ]; then
  echo "⚠️  Broken build detected. Last error:"
  tail -3 "$CRASH_LOG"
  echo "Booting last_good version in /doctor mode..."
  exec bash "$LAST_GOOD" --doctor
fi
exec bash "$CURRENT" "$@"
```

### `--self-test` flag (in src/27_main_repl.sh)
- Parse all source files (bash -n), verify config loads, exit 0
- Takes <1 second
- Added to main REPL as early-exit path

### `--doctor` mode (in src/24_agent_loop.sh or new src/28_doctor.sh)
- Reads crash log
- Runs `git diff HEAD~1` to see what changed
- Sends to LLM: "Fix this startup crash. Error: <crash_log>. Changes: <diff>"
- Applies fix, rebuilds, tests, installs
- If fix succeeds → new version becomes current
- If fix fails → report, stay on last_good

### Modified `build.sh`
1. Compile `mix.compiled`
2. Run `bash mix.compiled --self-test`
3. If healthy:
   - Copy current → last_good (if current exists)
   - Copy new → current
   - Symlink update
   - Install wrapper if not present
4. If broken: **don't update current**, print error, exit 1

### Version storage
```
~/.mix/versions/
├── 1714800000.bin       # timestamped backup
├── 1714801000.bin
├── current              # symlink → latest working
├── last_good            # symlink → previous working
```

### `/reload` update
After build, copy to `~/.mix/versions/$(date +%s).bin`, update current symlink, prune old.

## §V Invariants
- Wrapper never sources any mix code — pure bash, no deps
- `last_good` only updated after `--self-test` passes
- At most 5 versioned binaries stored
- `--doctor` runs from last_good (known good), never from broken binary
- If last_good is also broken (catastrophic), print manual recovery instructions

## §T Tasks
1. [ ] Add `--self-test` flag to main REPL (quick health check + exit)
2. [ ] Create wrapper script (`~/.local/bin/mix`) with health check + fallback
3. [ ] Modify `build.sh` to version binaries + health gate
4. [ ] Add `--doctor` mode (auto-fix broken builds)
5. [ ] Update `/reload` to integrate with versioning
6. [ ] Add auto-prune (keep 5 versions)
7. [ ] Test: intentionally break build, verify fallback
8. [ ] Update `install.sh` to install wrapper

## §B Bugs
- None yet
