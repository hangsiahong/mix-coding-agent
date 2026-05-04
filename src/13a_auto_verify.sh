# ─── Auto-Verify (post-edit verification) ────────────────────────────────────
# After edit_file/create_file succeeds, auto-run verification:
#   1. Syntax check (file-type specific, fast)
#   2. Type check (if typechecker available)
#   3. Lint (if linter configured)
#   4. Tests (if test runner detected + file is in test scope)
#
# Results appended to tool result so model sees them immediately.
# Controlled by AUTO_VERIFY env var (default: on).
# Toggle: /verify [on|off] in REPL.

AUTO_VERIFY="${AUTO_VERIFY:-on}"

# Map file extension → verification commands
# Returns: lines of "CHECK|<label>|<command>" or empty
_get_verify_cmds() {
  local file="$1"
  local ext="${file##*.}"
  local base="${file##*/}"

  case "$ext" in
    sh|bash)
      # shellcheck (static analysis)
      command -v shellcheck >/dev/null 2>&1 && echo "CHECK|shellcheck|shellcheck -f gcc -S warning '$file' 2>&1 | head -20"
      # bash -n (syntax check)
      echo "CHECK|syntax|bash -n '$file' 2>&1"
      ;;
    py)
      # python syntax check
      echo "CHECK|syntax|python3 -c 'import py_compile; py_compile.compile(\"$file\", doraise=True)' 2>&1"
      # ruff (fast linter)
      command -v ruff >/dev/null 2>&1 && echo "CHECK|ruff|ruff check '$file' 2>&1 | head -20"
      # mypy (type check) — only if mypy.ini or pyproject.toml config exists
      if [ -f "$WORKDIR/mypy.ini" ] || [ -f "$WORKDIR/pyproject.toml" ]; then
        command -v mypy >/dev/null 2>&1 && echo "CHECK|mypy|mypy '$file' --no-error-summary 2>&1 | head -15"
      fi
      ;;
    js|ts|jsx|tsx)
      local _has_node=true
      command -v node >/dev/null 2>&1 || _has_node=false
      # Syntax check via node --check (JS only)
      if [ "$_has_node" = true ] && [ "$ext" = "js" ]; then
        echo "CHECK|syntax|node --check '$file' 2>&1"
      fi
      # ESLint if available
      if [ -f "$WORKDIR/node_modules/.bin/eslint" ]; then
        echo "CHECK|eslint|node_modules/.bin/eslint --no-error-on-unmatched-pattern '$file' 2>&1 | head -20"
      fi
      # TypeScript: tsc --noEmit for .ts/.tsx
      if [ "$ext" = "ts" ] || [ "$ext" = "tsx" ]; then
        if [ -f "$WORKDIR/node_modules/.bin/tsc" ]; then
          echo "CHECK|tsc|node_modules/.bin/tsc --noEmit --pretty false 2>&1 | grep -F '$file' | head -15"
        fi
      fi
      ;;
    rs)
      # cargo check (fast, catches type errors)
      if [ -f "$WORKDIR/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
        echo "CHECK|cargo-check|cargo check --message-format=short 2>&1 | tail -20"
      fi
      ;;
    go)
      # go vet + go build
      if [ -f "$WORKDIR/go.mod" ] && command -v go >/dev/null 2>&1; then
        echo "CHECK|go-vet|go vet ./... 2>&1 | head -15"
        echo "CHECK|go-build|go build ./... 2>&1 | head -15"
      fi
      ;;
    rb)
      # ruby -c (syntax)
      command -v ruby >/dev/null 2>&1 && echo "CHECK|syntax|ruby -c '$file' 2>&1"
      ;;
    java)
      # javac syntax
      command -v javac >/dev/null 2>&1 && echo "CHECK|syntax|javac -d /tmp -sourcepath '$WORKDIR' '$file' 2>&1 | head -15"
      ;;
    c|cpp|cc|cxx|h|hpp)
      # gcc/clang syntax check
      local _compiler=""
      command -v g++ >/dev/null 2>&1 && _compiler="g++"
      command -v clang++ >/dev/null 2>&1 && _compiler="clang++"
      if [ -n "$_compiler" ]; then
        echo "CHECK|syntax|$_compiler -fsyntax-only -std=c++17 '$file' 2>&1 | head -15"
      fi
      ;;
  esac

  # ── Project-level test run (only if file is NOT a test file itself) ────
  # Heuristic: test files match *test*, *spec*, *_test.*, *Test.*
  local _is_test=false
  printf '%s' "$base" | grep -qiE '(test|spec)' && _is_test=true

  if [ "$_is_test" = false ] && [ -n "$TEST_CMD" ]; then
    # Only run tests if the edited file could affect tests
    # For now: always offer if TEST_CMD is set and file isn't a test
    case "$TEST_CMD" in
      npm\ test|npm\ test\ *)
        # Only for JS/TS files
        case "$ext" in js|ts|jsx|tsx|json)
          echo "CHECK|tests|$TEST_CMD 2>&1 | tail -25"
          ;;
        esac
        ;;
      pytest|pytest\ *)
        # Only for Python files
        case "$ext" in py)
          echo "CHECK|tests|$TEST_CMD 2>&1 | tail -25"
          ;;
        esac
        ;;
      *)
        # Generic: always run if we have a test command
        echo "CHECK|tests|$TEST_CMD 2>&1 | tail -25"
        ;;
    esac
  fi
}

# Run auto-verify for a file. Returns verification results string.
# Usage: auto_verify "/path/to/file.sh"
auto_verify() {
  local file="$1"
  [ "$AUTO_VERIFY" != "on" ] && return 0
  [ ! -f "$file" ] && return 0

  local cmds; cmds=$(_get_verify_cmds "$file")
  [ -z "$cmds" ] && return 0

  local results=""
  local _total_checks=0
  local _passed=0
  local _failed=0
  local NL=$'\n'

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local _label _cmd
    _label="${line#CHECK|}"
    _label="${_label%%|*}"
    # Strip "CHECK|<label>|" prefix (2 pipes)
    _cmd="${line#CHECK|${_label}|}"

    _total_checks=$((_total_checks + 1))

    # Run check with timeout (15s per check, 60s for tests)
    local _timeout=15
    [ "$_label" = "tests" ] && _timeout=60
    [ "$_label" = "cargo-check" ] && _timeout=30

    local _out _rc=0
    _out=$(timeout "$_timeout" bash -c "$_cmd" 2>&1) || _rc=$?

    # timeout returns 124 on timeout
    if [ "$_rc" = "124" ]; then
      results+="${NL}  ⏱ $_label: timed out (${_timeout}s)"
      _failed=$((_failed + 1))
      continue
    fi

    # Trim output
    local _trimmed
    _trimmed=$(printf '%s' "$_out" | head -10)
    local _out_len=${#_out}

    if [ "$_rc" -eq 0 ]; then
      _passed=$((_passed + 1))
      # Only show output if there are warnings (not clean)
      if [ -n "$_trimmed" ] && [ "$_label" != "syntax" ]; then
        # Check if output contains warnings
        if printf '%s' "$_trimmed" | grep -qiE 'warning|warn'; then
          results+="${NL}  ⚠ $_label: warnings"
          local _wline=0
          while IFS= read -r wl; do
            _wline=$((_wline + 1))
            [ "$_wline" -gt 5 ] && break
            results+="${NL}    $wl"
          done <<< "$_trimmed"
        fi
      fi
    else
      _failed=$((_failed + 1))
      results+="${NL}  ✗ $_label: failed (exit $_rc)"
      # Show first few lines of error output
      local _eline=0
      while IFS= read -r el; do
        _eline=$((_eline + 1))
        [ "$_eline" -gt 5 ] && break
        results+="${NL}    $el"
      done <<< "$_trimmed"
      [ "$_out_len" -gt 500 ] && results+="${NL}    ... ($_out_len bytes total)"
    fi
  done <<< "$cmds"

  # Build summary
  if [ "$_failed" -gt 0 ]; then
    printf '%s' "${NL}[VERIFY: ${_total_checks} checks, ${_passed} passed, ${_failed} FAILED]${results}"
  elif [ "$_total_checks" -gt 0 ] && [ -n "$results" ]; then
    printf '%s' "${NL}[VERIFY: ${_total_checks} checks passed]${results}"
  fi
  # If all passed and no warnings, return empty (don't clutter output)
}
