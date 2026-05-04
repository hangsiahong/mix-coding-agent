# ─── Test Generation Commands (/test) ──────────────────────────────────────

# Detect test framework for the project. Returns: framework|runner_cmd|config_file|test_dir_pattern|file_ext
_test_detect_framework() {
  local _dir="$1"

  # Node.js / TypeScript projects
  if [ -f "$_dir/package.json" ]; then
    local _deps
    _deps=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
deps = {**d.get('dependencies',{}), **d.get('devDependencies',{})}
names = [k for k in deps if k in ('vitest','jest','mocha','ava','tape','bun:test','@std/assert')]
if not names:
    # Check scripts for hints
    scripts = d.get('scripts',{})
    test_script = scripts.get('test','')
    if 'vitest' in test_script: names=['vitest']
    elif 'jest' in test_script: names=['jest']
    elif 'mocha' in test_script: names=['mocha']
if names: print(names[0])
" "$_dir/package.json" 2>/dev/null) || true

    if [ "$_deps" = "vitest" ]; then
      echo "vitest|npx vitest run|vitest.config.ts|src/__tests__|.test.ts"
      return
    fi
    if [ "$_deps" = "jest" ]; then
      echo "jest|npx jest|jest.config.js|__tests__|.test.js"
      return
    fi
    if [ "$_deps" = "mocha" ]; then
      echo "mocha|npx mocha|.mocharc.yml|test|.test.js"
      return
    fi
    # TypeScript project with no test framework — recommend vitest
    if [ -f "$_dir/tsconfig.json" ]; then
      echo "none_ts|vitest|vitest.config.ts|src/__tests__|.test.ts"
      return
    fi
    # JavaScript project with no test framework — recommend jest
    echo "none_js|jest|jest.config.js|__tests__|.test.test.js"
    return
  fi

  # Python projects
  if [ -f "$_dir/pyproject.toml" ] || [ -f "$_dir/setup.py" ] || [ -f "$_dir/requirements.txt" ]; then
    # Check for pytest
    local _has_pytest=false
    { [ -f "$_dir/pytest.ini" ] || [ -f "$_dir/conftest.py" ]; } && _has_pytest=true
    [ "$_has_pytest" = false ] && grep -qi 'pytest' "$_dir/requirements.txt" "$_dir/pyproject.toml" 2>/dev/null && _has_pytest=true
    if [ "$_has_pytest" = true ]; then
      echo "pytest|python -m pytest|pytest.ini|tests|_test.py"
      return
    fi
    # Check for unittest (stdlib, always available)
    echo "unittest|python -m unittest|none|tests|_test.py"
    return
  fi

  # Go projects
  if [ -f "$_dir/go.mod" ]; then
    echo "go_test|go test ./...|none|.|_test.go"
    return
  fi

  # Rust projects
  if [ -f "$_dir/Cargo.toml" ]; then
    echo "cargo_test|cargo test|Cargo.toml|tests|.rs"
    return
  fi

  # Ruby projects
  if [ -f "$_dir/Gemfile" ]; then
    echo "rspec|bundle exec rspec|.rspec|spec|_spec.rb"
    return
  fi

  # Bash scripts (default fallback)
  echo "bats|bats|none|tests|.bats"
}

# Install test framework if not present
_test_install_framework() {
  local _dir="$1" _fw="$2"
  case "$_fw" in
    vitest)
      echo "  Installing vitest..."
      (cd "$_dir" && npm install -D vitest 2>&1 | tail -3)
      ;;
    jest)
      echo "  Installing jest..."
      (cd "$_dir" && npm install -D jest 2>&1 | tail -3)
      ;;
    mocha)
      echo "  Installing mocha..."
      (cd "$_dir" && npm install -D mocha 2>&1 | tail -3)
      ;;
    pytest)
      echo "  Installing pytest..."
      pip install pytest 2>&1 | tail -3
      ;;
    bats)
      echo "  Installing bats-core..."
      (cd "$_dir" && npm install -D bats 2>&1 | tail -3 || git clone --depth 1 https://github.com/bats-core/bats-core.git tests/.bats 2>/dev/null)
      ;;
    *)
      # Framework doesn't need install (go test, cargo test, unittest, rspec)
      echo "  No installation needed for $_fw (built-in or manual)"
      ;;
  esac
}

# Generate vitest config
_test_gen_vitest_config() {
  local _dir="$1"
  local _cfg="$_dir/vitest.config.ts"
  if [ ! -f "$_cfg" ]; then
    cat > "$_cfg" << 'VITEST_EOF'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    include: ['src/**/*.{test,spec}.{ts,tsx,js,jsx}'],
  },
})
VITEST_EOF
    echo "$_cfg"
  fi
}

# Generate jest config
_test_gen_jest_config() {
  local _dir="$1"
  local _cfg="$_dir/jest.config.js"
  if [ ! -f "$_cfg" ]; then
    cat > "$_cfg" << 'JEST_EOF'
/** @type {import('jest').Config} */
module.exports = {
  testMatch: ['**/__tests__/**/*.test.js', '**/?(*.)+(spec|test).js'],
  transform: {},
};
JEST_EOF
    echo "$_cfg"
  fi
}

# Add test script to package.json if missing
_test_ensure_script() {
  local _dir="$1" _cmd="$2"
  [ ! -f "$_dir/package.json" ] && return
  python3 -c "
import json, sys
f = sys.argv[1]
cmd = sys.argv[2]
with open(f) as fh: d = json.load(fh)
scripts = d.setdefault('scripts', {})
if 'test' not in scripts or scripts['test'] in ('echo \"Error: no test specified\" && exit 1', 'echo \\\\\"Error: no test specified\\\\\" && exit 1'):
    scripts['test'] = cmd
    with open(f, 'w') as fh:
        json.dump(d, fh, indent=2)
        fh.write('\n')
    print('added')
else:
    print('exists')
" "$_dir/package.json" "$_cmd" 2>/dev/null
}

# Main /test handler
handle_test_cmd() {
  local _cmd="$1"
  local _sub="${_cmd#/test}"; _sub="${_sub# }"

  case "$_sub" in
    init)
      _test_init "$WORKDIR"
      ;;
    run)
      _test_run "$WORKDIR"
      ;;
    generate\ --bg*)
      local _target="${_sub#generate --bg}"; _target="${_target# }"
      _test_generate_bg "$WORKDIR" "$_target"
      ;;
    generate*)
      local _target="${_sub#generate}"; _target="${_target# }"
      _test_generate "$WORKDIR" "$_target"
      ;;
    coverage)
      _test_coverage "$WORKDIR"
      ;;
    "")
      echo -e "  \033[1;37m/test\033[0m — test generation & runner"
      echo ""
      echo "  /test init              Detect framework, scaffold test structure, write first tests"
      echo "  /test generate          Generate tests for recently changed files"
      echo "  /test generate <file>   Generate tests for specific file"
      echo "  /test generate --bg     Generate in background (subagent)"
      echo "  /test run               Run existing test suite"
      echo "  /test coverage          Run tests + show untested files"
      ;;
    *)
      echo "  Unknown: /test $_sub"
      echo "  Use: /test [init|generate|run|coverage]"
      ;;
  esac
}

# /test init — detect, install, scaffold, write first tests, run them
_test_init() {
  local _dir="$1"
  local _det; _det=$(_test_detect_framework "$_dir")
  local _fw="${det%%|*}"

  # Parse detection result
  local _fw_name _runner _config _testdir _ext
  IFS='|' read -r _fw_name _runner _config _testdir _ext <<< "$_det"

  echo -e "  \033[1;37m─── Test Init ───\033[0m"

  # Framework already installed?
  local _needs_install=false
  case "$_fw_name" in
    none_ts) _fw_name="vitest"; _runner="npx vitest run"; _needs_install=true ;;
    none_js) _fw_name="jest"; _runner="npx jest"; _needs_install=true ;;
  esac

  # Show detection
  local _lang="unknown"
  [ -f "$_dir/package.json" ] && _lang="Node.js"
  [ -f "$_dir/tsconfig.json" ] && _lang="TypeScript"
  [ -f "$_dir/go.mod" ] && _lang="Go"
  [ -f "$_dir/Cargo.toml" ] && _lang="Rust"
  [ -f "$_dir/pyproject.toml" ] || [ -f "$_dir/requirements.txt" ] && _lang="Python"
  [ -f "$_dir/Gemfile" ] && _lang="Ruby"

  echo -e "  \033[38;5;82m✓\033[0m Detected: $_lang"
  echo -e "  \033[38;5;82m✓\033[0m Framework: $_fw_name"

  # Install if needed
  if [ "$_needs_install" = true ]; then
    echo -e "  \033[0;33m⚠\033[0m No test framework found — installing $_fw_name"
    _test_install_framework "$_dir" "$_fw_name"
  fi

  # Generate config files
  local _created=()
  case "$_fw_name" in
    vitest)
      local _cfgf; _cfgf=$(_test_gen_vitest_config "$_dir")
      [ -n "$_cfgf" ] && _created+=("$(_cfgf)")
      _test_ensure_script "$_dir" "vitest run"
      ;;
    jest)
      local _cfgf; _cfgf=$(_test_gen_jest_config "$_dir")
      [ -n "$_cfgf" ] && _created+=("$(_cfgf)")
      _test_ensure_script "$_dir" "jest"
      ;;
  esac

  # Create test directory
  mkdir -p "$_dir/$_testdir" 2>/dev/null

  # Now delegate to LLM to write the actual first tests
  echo -e "  \033[38;5;99m⚡\033[0m Generating first tests..."
  echo ""

  local _init_prompt="[TEST INIT] Project: $_dir | Language: $_lang | Framework: $_fw_name | Test dir: $_testdir | File ext: $_ext

Your job: write meaningful first tests for this project.

Steps:
1. Read the project structure (list_files, read key source files).
2. Identify 3-5 core functions/modules that are most testable.
3. For each, create a test file in $_testdir/ using $_fw_name conventions.
   - Use human-readable test names that describe behavior.
   - Test happy path + at least 1 edge case per function.
   - Import the actual module/function being tested.
4. Write the files using create_file.
5. Run the test suite with: $_runner
6. Report results.

Rules:
- Only test source code, not config or boilerplate.
- Test names must be descriptive: 'calculates total with tax' not 'test1'.
- Each test must be independent (no order dependencies).
- If you need to mock something, use the framework's built-in mocking.
- If a test fails, fix it before finishing.
- At the end, print a summary: how many tests, how many passing, what files were created."

  run_agent "$_init_prompt"
}

# /test run — execute test suite
_test_run() {
  local _dir="$1"
  local _det; _det=$(_test_detect_framework "$_dir")
  local _fw_name _runner _rest
  IFS='|' read -r _fw_name _runner _rest <<< "$_det"

  # Handle recommended-but-not-installed
  case "$_fw_name" in
    none_ts|none_js)
      echo -e "  \033[1;31m✗\033[0m No test framework installed."
      echo "  Run /test init first."
      return
      ;;
  esac

  echo -e "  \033[1;37mRunning $_fw_name...\033[0m"
  echo "  Command: $_runner"
  echo ""

  local _result; _result=$(cd "$_dir" && bash -c "$_runner" 2>&1)
  local _ec=$?

  if [ $_ec -eq 0 ]; then
    echo -e "  \033[38;5;82m✓ Tests passed\033[0m"
  else
    echo -e "  \033[1;31m✗ Tests failed (exit $_ec)\033[0m"
  fi
  echo "$_result" | tail -30
}

# /test generate [file] — generate tests for target files
_test_generate() {
  local _dir="$1"
  local _target="$2"
  local _det; _det=$(_test_detect_framework "$_dir")
  local _fw_name _runner _config _testdir _ext
  IFS='|' read -r _fw_name _runner _config _testdir _ext <<< "$_det"

  case "$_fw_name" in
    none_ts|none_js)
      echo -e "  \033[1;31m✗\033[0m No test framework installed."
      echo "  Run /test init first."
      return
      ;;
  esac

  # Determine target files
  local _gen_prompt
  if [ -n "$_target" ] && [ -f "$_dir/$_target" ]; then
    _gen_prompt="[TEST GENERATE] Generate tests for: $_target
Project: $_dir | Framework: $_fw_name | Test dir: $_testdir | File ext: $_ext

Steps:
1. Read $_target carefully.
2. Identify all exported/public functions, classes, and methods.
3. Create test file at $_testdir/$(basename "${_target%.*}")$_ext.
4. For each function/method:
   - Test happy path
   - Test edge cases (empty input, null, wrong type, boundary values)
   - Test error handling
5. Use descriptive test names describing the behavior.
6. Run tests with: $_runner
7. Fix any failures. All tests must pass.

Rules:
- Test names: 'does X when Y' format. Never 'test1', 'test_function'.
- Each test independent. No shared mutable state.
- Use framework's built-in assertions and mocking.
- If the function is simple, 2-3 tests suffice. If complex, 5-8 tests.
- Print summary at end: files created, tests written, all passing."
  else
    # No specific file — generate for recently changed files
    _gen_prompt="[TEST GENERATE] Generate tests for recently changed files.
Project: $_dir | Framework: $_fw_name | Test dir: $_testdir | File ext: $_ext

Steps:
1. Find recently changed source files:
   - If git: git diff --name-only HEAD~5 (last 5 commits)
   - Otherwise: list source files in project root
2. For each source file that doesn't already have a corresponding test file:
   - Read the source file
   - Identify exported/public functions
   - Create test file at $_testdir/<name>$_ext
   - Write tests: happy path + edge cases per function
3. Run all tests with: $_runner
4. Fix failures. All must pass.
5. Print summary.

Rules:
- Skip files that already have test files (don't overwrite).
- Test names: descriptive behavior format.
- Each test independent.
- 3-5 tests per source file minimum."
  fi

  run_agent "$_gen_prompt"
}

# /test generate --bg [file] — background test generation via subagent
_test_generate_bg() {
  local _dir="$1"
  local _target="$2"

  if [ -z "$TMUX" ]; then
    echo -e "  \033[1;31m✗\033[0m Background mode requires tmux. Run mix inside tmux."
    return
  fi

  local _det; _det=$(_test_detect_framework "$_dir")
  local _fw_name _runner _config _testdir _ext
  IFS='|' read -r _fw_name _runner _config _testdir _ext <<< "$_det"

  case "$_fw_name" in
    none_ts|none_js)
      echo -e "  \033[1;31m✗\033[0m No test framework installed. Run /test init first."
      return
      ;;
  esac

  local _task_desc="Generate tests"
  [ -n "$_target" ] && _task_desc="Generate tests for $_target"

  local _bg_prompt="[TEST GENERATE — BACKGROUND] Project: $_dir | Framework: $_fw_name | Test dir: $_testdir | File ext: $_ext | Target: ${_target:-recently changed files}

1. Find target source files: ${_target:-use git diff --name-only HEAD~5 or list source files}
2. For each without existing test: read source, create test file in $_testdir/.
3. Write descriptive tests (happy path + edge cases).
4. Run tests with: $_runner. Fix failures.
5. Append summary to memorybank/log.md if it exists: format '## [$(date +%Y-%m-%d)] test-gen | <files> | <N> tests generated'

Rules: descriptive test names, independent tests, 3-5 per file minimum."

  # Use the same subagent pattern as /afk
  local _worker_tmp; _worker_tmp=$(mktemp -t mix-testgen-XXXXXX.sh)
  local _prompt_tmp; _prompt_tmp=$(mktemp -t mix-testgen-XXXXXX.txt)
  printf '%s' "$_bg_prompt" > "$_prompt_tmp"

  local MIX_BIN; MIX_BIN=$(command -v mix 2>/dev/null || echo "./mix")
  [ ! -x "$MIX_BIN" ] && MIX_BIN="$PWD/mix"
  [ ! -x "$MIX_BIN" ] && { echo "  Error: mix binary not found"; rm -f "$_worker_tmp" "$_prompt_tmp"; return; }

  local _mytty; _mytty=$(tty 2>/dev/null || echo "")

  cat > "$_worker_tmp" << TESTGEN_WORKER_EOF
#!/usr/bin/env bash
PROMPT_FILE="\$1"; WORK_DIR="\$2"; MY_TTY="\$3"; LOG_FILE="/tmp/mix-testgen.log"
cd "\$WORK_DIR" || exit 1
printf '[test-gen] Starting... %%s\n' "\$(date)" | tee "\$LOG_FILE"
MIX_YOLO=1 "$MIX_BIN" < "\$PROMPT_FILE" 2>&1 | tee -a "\$LOG_FILE"
printf '[test-gen] Done. %%s\n' "\$(date)" | tee -a "\$LOG_FILE"
[ -n "\$MY_TTY" ] && printf '\n  \033[38;5;82m✓ Test generation done! Check /test run or /workers\033[0m\n' > "\$MY_TTY" 2>/dev/null || true
TESTGEN_WORKER_EOF
  chmod +x "$_worker_tmp"

  tmux new-window -n "mix-testgen" \
    "bash '$_worker_tmp' '$_prompt_tmp' '$_dir' '$_mytty'; rm -f '$_prompt_tmp' '$_worker_tmp'" \
    2>/dev/null

  if [ $? -eq 0 ]; then
    echo -e "  \033[38;5;99m⚡\033[0m Test generation running in background"
    echo "  Worker: mix-testgen"
    echo "  Log:    /tmp/mix-testgen.log"
    echo "  Check:  /workers or tail -f /tmp/mix-testgen.log"
  else
    echo "  Failed to spawn background worker."
    rm -f "$_worker_tmp" "$_prompt_tmp"
  fi
}

# /test coverage — run tests + show untested files
_test_coverage() {
  local _dir="$1"
  local _det; _det=$(_test_detect_framework "$_dir")
  local _fw_name _runner _config _testdir _ext
  IFS='|' read -r _fw_name _runner _config _testdir _ext <<< "$_det"

  case "$_fw_name" in
    none_ts|none_js)
      echo -e "  \033[1;31m✗\033[0m No test framework installed. Run /test init first."
      return
      ;;
  esac

  echo -e "  \033[1;37m─── Test Coverage ───\033[0m"

  # Run coverage if framework supports it
  local _cov_runner="$_runner"
  case "$_fw_name" in
    vitest) _cov_runner="npx vitest run --coverage" ;;
    jest)   _cov_runner="npx jest --coverage" ;;
    pytest) _cov_runner="python -m pytest --cov=. --cov-report=term-missing" ;;
    go_test) _cov_runner="go test ./... -coverprofile=coverage.out && go tool cover -func=coverage.out" ;;
    cargo_test) _cov_runner="cargo tarpaulin" ;;
    *) echo "  Coverage not auto-supported for $_fw_name. Showing file-level analysis." ;;
  esac

  echo "  Running: $_cov_runner"
  echo ""
  (cd "$_dir" && bash -c "$_cov_runner" 2>&1) | tail -40

  # Always show untested files analysis
  echo ""
  echo -e "  \033[1;37mUntested source files:\033[0m"

  local _src_count=0 _tested_count=0
  local _src_files
  case "$_fw_name" in
    vitest|jest|mocha)
      # Find JS/TS source files without corresponding test files
      while IFS= read -r _src; do
        [ -z "$_src" ] && continue
        _src_count=$((_src_count + 1))
        local _base; _base=$(basename "${_src%.*}")
        local _found_test=false
        # Check multiple test patterns
        for _tdir in "$_testdir" "tests" "test" "__tests__" "src/__tests__"; do
          for _text in ".test." ".spec."; do
            if find "$_dir/$_tdir" -name "${_base}${_text}*" 2>/dev/null | grep -q .; then
              _found_test=true; break 2
            fi
          done
        done
        if [ "$_found_test" = false ]; then
          echo -e "    \033[0;33m⚠\033[0m $_src"
        else
          _tested_count=$((_tested_count + 1))
        fi
      done < <(find "$_dir/src" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        ! -name "*.test.*" ! -name "*.spec.*" ! -name "*.d.ts" 2>/dev/null | head -50)
      ;;
    pytest|unittest)
      while IFS= read -r _src; do
        [ -z "$_src" ] && continue
        _src_count=$((_src_count + 1))
        local _base; _base=$(basename "${_src%.py}")
        local _found_test=false
        for _tdir in "$_testdir" "tests" "test"; do
          if [ -f "$_dir/$_tdir/${_base}_test.py" ] || [ -f "$_dir/$_tdir/test_${_base}.py" ]; then
            _found_test=true; break
          fi
        done
        if [ "$_found_test" = false ]; then
          echo -e "    \033[0;33m⚠\033[0m $_src"
        else
          _tested_count=$((_tested_count + 1))
        fi
      done < <(find "$_dir" -type f -name "*.py" ! -name "test_*" ! -name "*_test.py" ! -path "*/.*" ! -path "*/venv/*" ! -path "*/__pycache__/*" 2>/dev/null | head -50)
      ;;
    go_test)
      while IFS= read -r _src; do
        [ -z "$_src" ] && continue
        _src_count=$((_src_count + 1))
        if [ ! -f "${_src%.go}_test.go" ]; then
          echo -e "    \033[0;33m⚠\033[0m $_src"
        else
          _tested_count=$((_tested_count + 1))
        fi
      done < <(find "$_dir" -type f -name "*.go" ! -name "*_test.go" ! -path "*/vendor/*" 2>/dev/null | head -50)
      ;;
    *)
      echo "    (file-level analysis not implemented for $_fw_name)"
      ;;
  esac

  if [ "$_src_count" -gt 0 ]; then
    local _pct=$(( _tested_count * 100 / _src_count ))
    echo ""
    echo -e "  Coverage: \033[1;37m$_tested_count/$_src_count\033[0m files tested ($_pct%)"
  else
    echo "    No source files found."
  fi
}
