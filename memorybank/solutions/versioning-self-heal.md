# Versioning & Self-Heal System

## What
Versioned binary storage with health-gated builds and automatic fallback to last known good binary. Prevents broken builds from breaking the user's workflow.

## Components

### `--self-test` flag (`src/00_header.sh`)
- Runs at top of compiled binary before any other code
- Checks: `python3` exists, `curl` exists
- Prints `OK` (exit 0) or `FAIL:...` (exit 1)
- Also handles `--doctor` (sets `_DOCTOR_MODE=true`) and `--version`

### Versioned storage (`~/.mix/versions/`)
- Timestamped `.bin` files (`<epoch>.bin`)
- `current` symlink → latest healthy binary
- `last_good` symlink → previous `current` (the one before this build)
- Auto-prune: keep last 5, never delete `current` or `last_good` targets

### Build pipeline (`build.sh`)
1. Concatenate `src/*.sh` → `mix.compiled` → `mix`
2. Inject `MIX_VERSION='YYYYMMDDHHMM'` as second line
3. **Health gate**: `bash mix --self-test` — abort if failed (no versioning)
4. Copy → `~/.mix/versions/<ts>.bin`
5. Rotate: old `current` → `last_good`, new → `current`
6. Auto-prune old `.bin` files (keep 5)
7. Install thin wrapper to `~/.local/bin/mix`

### Thin wrapper (`~/.local/bin/mix`)
- ~30 lines, **never breaks**
- Health-checks `current` with 3s timeout
- If broken: prints crash log, falls back to `last_good --doctor`
- If no `last_good`: prints recovery instructions, exit 1
- Crash log at `/tmp/mix-crash.log`

### `--doctor` mode (`src/26_banner.sh`)
- Shows crash log excerpt (5 lines)
- Tells user they can `/reload` or ask agent to fix
- Set by wrapper when falling back from broken `current`

### `/reload` integration (`src/25_repl_commands.sh`)
- Runs `bash build.sh`, pipes output
- Detects `Self-test FAILED` → prints error, stays on current version
- On success: session_save → exec new binary

### Install pipeline (`install.sh`)
- `download()` → temp file
- `health_check()` → `--self-test` with 5s timeout
- `version_install()` → `~/.mix/versions/<ts>.bin`, symlinks, prune
- `install_wrapper()` → thin wrapper to PATH

## Invariants
- Self-test runs before any versioning or installation
- `current` and `last_good` never point to same file
- Prune never removes symlink targets
- Wrapper is always ~30 lines of simple bash — no dependencies
- `MIX_VERSION` embedded in binary, displayed by `--version`
