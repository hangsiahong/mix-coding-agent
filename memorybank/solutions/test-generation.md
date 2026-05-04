# Test Generation System (/test)

**Date**: 2025-07-14
**File**: `src/26a_test_commands.sh` (568 lines)
**Impact**: Zero-to-tested in one command. Targets developers who never write tests.

## Commands

| Command | Description |
|---|---|
| `/test init` | Detect framework, scaffold config, write first tests, run them |
| `/test generate` | Generate tests for recently changed files |
| `/test generate <file>` | Generate tests for specific file |
| `/test generate --bg` | Generate in background via tmux subagent |
| `/test run` | Execute existing test suite |
| `/test coverage` | Run tests + show untested files analysis |

## Framework Detection

Auto-detects from project files:
- **package.json** → vitest, jest, mocha (installed) or recommends vitest/jest (not installed)
- **tsconfig.json** → recommends vitest for TS
- **pyproject.toml/requirements.txt** → pytest (installed) or unittest (stdlib fallback)
- **go.mod** → go test (built-in)
- **Cargo.toml** → cargo test (built-in)
- **Gemfile** → rspec

Returns: `framework|runner_cmd|config_file|test_dir|file_ext`

## /test init Flow

1. Detect language + framework
2. Install framework if missing (`npm install -D vitest/jest` etc)
3. Generate config files (vitest.config.ts, jest.config.js)
4. Add `test` script to package.json if missing
5. Delegate to LLM: read source files, write 3-5 test files with descriptive names
6. LLM runs test suite, fixes failures, reports results

## /test generate Flow

- **No target**: finds recently changed files via `git diff --name-only HEAD~5`
- **Specific file**: reads that file, generates targeted tests
- LLM writes tests with descriptive names, runs suite, fixes failures

## /test generate --bg

Spawns tmux subagent (`mix-testgen` window):
- Full mix instance with `MIX_YOLO=1`
- Logs to `/tmp/mix-testgen.log`
- Sends TTY notification on completion
- Appends to `memorybank/log.md` if exists

## /test coverage

- Runs framework-specific coverage command (vitest --coverage, pytest --cov, etc)
- Falls back to file-level analysis if coverage tool not available
- Scans source files, checks for corresponding test files
- Reports: X/Y files tested (Z%)

## Design Decisions

- **Descriptive test names enforced**: LLM prompt requires "does X when Y" format
- **First run must pass**: green output = dopamine = user comes back
- **No overwriting**: `generate` skips files that already have tests
- **Init installs framework**: removes the "I don't know how to set up testing" barrier
- **LLM does the writing**: framework-specific boilerplate is LLM's problem, not the user's

## Integration

- `build.sh`: sources 26a_test_commands.sh before 26_banner.sh
- `src/25_repl_commands.sh`: `/test*` case → `handle_test_cmd()`
- `src/27_main_repl.sh`: `/test` in tab completion
- `src/25_repl_commands.sh`: `/help` updated with testing section

## Files

- `src/26a_test_commands.sh` — new (568 lines)
- `src/25_repl_commands.sh` — +4 lines (case handler + help text)
- `src/27_main_repl.sh` — +1 char (tab completion)
- `build.sh` — +1 line (source inclusion)
