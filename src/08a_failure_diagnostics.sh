# ─── Smart Failure Diagnostics ────────────────────────────────────────────────
# After bash failure, analyze error output and inject structured diagnostics.
# Pattern-based: detects common failure modes and suggests specific fixes.
# Appended to bash tool result when [FAILED] detected.

# Analyze failed command output and return diagnostic hints
diagnose_failure() {
  local cmd="$1"
  local output="$2"
  local exit_code="$3"
  local hints=""
  local NL=$'\n'

  # ── Pattern: command not found ──────────────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'command not found|not found$'; then
    local _bin; _bin=$(printf '%s' "$cmd" | awk '{print $1}')
    local _alternatives=""
    # Check common alternatives
    case "$_bin" in
      python)  command -v python3 >/dev/null 2>&1 && _alternatives="python3" ;;
      pip)     command -v pip3 >/dev/null 2>&1 && _alternatives="pip3" ;;
      node)    command -v node >/dev/null 2>&1 || _alternatives="node not installed" ;;
      npm)     command -v npm >/dev/null 2>&1 || _alternatives="npm not installed" ;;
      cargo)   command -v cargo >/dev/null 2>&1 || _alternatives="cargo not installed (rustup.rs)" ;;
      docker)  command -v podman >/dev/null 2>&1 && _alternatives="podman (docker alias)" ;;
      *)
        # Check if binary exists elsewhere
        local _found; _found=$(command -v "$_bin" 2>/dev/null) || true
        if [ -n "$_found" ]; then
          _alternatives="found at $_found (check PATH or use full path)"
        else
          # Check if it's an npm/node package
          if [ -f "$WORKDIR/node_modules/.bin/$_bin" ]; then
            _alternatives="found in node_modules/.bin/$_bin (use npx or add to PATH)"
          fi
        fi
        ;;
    esac
    hints+="${NL}  💡 Command '$_bin' not found."
    [ -n "$_alternatives" ] && hints+=" Alternative: $_alternatives"
  fi

  # ── Pattern: permission denied ──────────────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'permission denied|EACCES|access denied'; then
    hints+="${NL}  💡 Permission denied. Fix: check file permissions (ls -la), or use chmod/chown."
    # Check if it's a common fixable case
    local _target; _target=$(printf '%s' "$output" | grep -oE '/[^ :]+' | head -1) || true
    if [ -n "$_target" ] && [ -e "$_target" ]; then
      local _perms; _perms=$(ls -la "$_target" 2>/dev/null | awk '{print $1, $3, $4}') || true
      hints+="${NL}     Target: $_target ($_perms)"
    fi
  fi

  # ── Pattern: no such file or directory ───────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'no such file|not found:'; then
    local _missing; _missing=$(printf '%s' "$output" | grep -oE '(/[^ :"]+|~[^ :"]+)' | head -3) || true
    if [ -n "$_missing" ]; then
      hints+="${NL}  💡 Missing path: $_missing"
      # Suggest similar files
      local _parent; _parent=$(dirname "$_missing" 2>/dev/null) || true
      if [ -d "$_parent" ]; then
        local _similar; _similar=$(ls "$_parent" 2>/dev/null | head -5) || true
        [ -n "$_similar" ] && hints+="${NL}     Available in $_parent: $_similar"
      fi
    fi
  fi

  # ── Pattern: syntax error (various languages) ───────────────────────────
  if printf '%s' "$output" | grep -qiE 'syntax error|SyntaxError|ParseError|syntax error near'; then
    local _file _line
    _file=$(printf '%s' "$output" | grep -oE '(^|File "|[^ ]+/)[^ "]+' | grep -vE '(python|node|ruby|bash)$' | head -1) || true
    _line=$(printf '%s' "$output" | grep -oE '(line |:)[0-9]+' | grep -oE '[0-9]+' | head -1) || true
    hints+="${NL}  💡 Syntax error"
    [ -n "$_file" ] && hints+=" in $_file"
    [ -n "$_line" ] && hints+=" at line $_line"
    hints+=". Check for missing brackets, quotes, or indentation."
  fi

  # ── Pattern: module/package not found ───────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'ModuleNotFoundError|ImportError|Cannot find module|no module named'; then
    local _mod
    _mod=$(printf '%s' "$output" | grep -oE "(named |module )'[^']*" | sed "s/.*'//" | head -1) || true
    [ -z "$_mod" ] && _mod=$(printf '%s' "$output" | grep -oE "Cannot find module '([^']+)'" | sed "s/.*'//;s/'.*//" | head -1) || true
    if [ -n "$_mod" ]; then
      hints+="${NL}  💡 Module '$_mod' not found."
      # Suggest install command based on project type
      if [ -f "$WORKDIR/requirements.txt" ] || [ -f "$WORKDIR/pyproject.toml" ]; then
        hints+="${NL}     Fix: pip install $_mod"
      elif [ -f "$WORKDIR/package.json" ]; then
        hints+="${NL}     Fix: npm install $_mod"
      fi
    fi
  fi

  # ── Pattern: port already in use ────────────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'address already in use|EADDRINUSE|port.*already'; then
    local _port; _port=$(printf '%s' "$output" | grep -oE '[0-9]{4,5}' | head -1) || true
    if [ -n "$_port" ]; then
      hints+="${NL}  💡 Port $_port in use. Fix: kill process with 'lsof -i :$_port' or 'fuser -k $_port/tcp'"
    fi
  fi

  # ── Pattern: disk full ──────────────────────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'no space left|ENOSPC|disk full'; then
    hints+="${NL}  💡 Disk full. Check: df -h, du -sh * | sort -h"
  fi

  # ── Pattern: network/connection errors ──────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'connection refused|ECONNREFUSED|network.*unreachable|ETIMEDOUT'; then
    local _host; _host=$(printf '%s' "$output" | grep -oE 'localhost:[0-9]+|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | head -1) || true
    hints+="${NL}  💡 Connection refused"
    [ -n "$_host" ] && hints+=" to $_host"
    hints+=". Check: is the service running?"
  fi

  # ── Pattern: git merge conflict ─────────────────────────────────────────
  if printf '%s' "$output" | grep -qiE 'merge conflict|CONFLICT'; then
    hints+="${NL}  💡 Merge conflicts detected. Fix: edit conflicted files, then git add + git commit"
  fi

  # ── Pattern: TypeScript/JavaScript specific ─────────────────────────────
  if printf '%s' "$output" | grep -qiE 'Type.*is not assignable|Property.*does not exist'; then
    hints+="${NL}  💡 TypeScript type error. Fix: check type definitions, add type assertions, or fix the type mismatch."
  fi

  # ── Return hints if any ─────────────────────────────────────────────────
  if [ -n "$hints" ]; then
    printf '%s' "[DIAGNOSTIC]$hints"
  fi
}
