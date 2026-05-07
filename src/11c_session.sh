# ─── Session Persistence (/resume) ───────────────────────────────────────────
# Saves session state on exit, restores on /resume.
# File cache, repo map, env info, config — all survive restart.
# Session file: .mix/session.json (gitignored, < 50KB)
# Defines persistence across restarts.

_SESSION_FILE=".mix/session.json"
_SESSION_VERSION=1
_SESSION_AVAILABLE=false
export _SESSION_AVAILABLE

# Save current session state to disk
session_save() {
  # Don't save in piped mode or if no meaningful state
  [ "$INTERACTIVE" = false ] && return
  local _cache_size=${#_FILE_CACHE}
  # Truncate file cache if too large (keep under 40KB to leave room for rest)
  local _save_cache="$_FILE_CACHE"
  if [ "$_cache_size" -gt 40000 ]; then
    _save_cache=$(printf '%s' "$_FILE_CACHE" | python3 -c '
import json, sys
cache = json.loads(sys.stdin.read())
order = sys.argv[1].split()
keep = order[-4:] if len(order) > 4 else order
filtered = {k: v for k, v in cache.items() if k in keep}
print(json.dumps(filtered))
' "$_FILE_CACHE_ORDER" 2>/dev/null) || _save_cache='{}'
    local _new_order=""
    for _fp in $_FILE_CACHE_ORDER; do
      if printf '%s' "$_save_cache" | grep -qF "\"$_fp\""; then
        _new_order="${_new_order:+$_new_order }$_fp"
      fi
    done
    _FILE_CACHE_ORDER="$_new_order"
  fi

  local _branch=""
  [ "$GIT_ENABLED" = true ] && _branch=$(git -C "$WORKDIR" branch --show-current 2>/dev/null || echo "?")

  local _sess_tmp; _sess_tmp=$(mktemp -t mix-$$-session-XXXXXX)
  python3 -c '
import json, sys, os, time
data = {
    "version": 1,
    "timestamp": int(time.time()),
    "env_info": sys.argv[1],
    "git_enabled": sys.argv[2] == "true",
    "git_branch": sys.argv[3],
    "provider": sys.argv[4],
    "model": sys.argv[5],
    "base_url": sys.argv[6],
    "caveman_mode": sys.argv[7],
    "agent_mode": sys.argv[8],
    "auto_yes": sys.argv[9] == "true",
    "active_skills": sys.argv[10],
    "file_cache": json.loads(sys.argv[11]),
    "file_cache_order": sys.argv[12],
    "repo_map": sys.argv[13],
    "repo_map_mtimes": sys.argv[14],
    "repo_map_time": int(sys.argv[15]),
    "last_input": sys.argv[16],
    "cwd": sys.argv[17]
}
os.makedirs(os.path.dirname(sys.argv[18]), exist_ok=True)
with open(sys.argv[18], "w") as f:
    json.dump(data, f)
' "$ENV_INFO" "$GIT_ENABLED" "$_branch" "$PROVIDER" "$MODEL" "$BASE_URL" \
  "$CAVEMAN_MODE" "$AGENT_MODE" "$AUTO_YES" "$ACTIVE_SKILLS" \
  "$_save_cache" "$_FILE_CACHE_ORDER" "$_REPO_MAP" "$_REPO_MAP_MTIMES" \
  "$_REPO_MAP_TIME" "${_LAST_INPUT:-}" "$WORKDIR" "$_sess_tmp" 2>/dev/null || {
    rm -f "$_sess_tmp"
    return 1
  }

  mkdir -p .mix 2>/dev/null || true
  mv "$_sess_tmp" "$_SESSION_FILE" 2>/dev/null || rm -f "$_sess_tmp"
}

# Load session from disk — stores restore data (not applied until /resume)
session_load() {
  [ ! -f "$_SESSION_FILE" ] && return 1

  # Validate JSON
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_SESSION_FILE" 2>/dev/null || {
    echo "  Warning: session file corrupted, skipping."
    return 1
  }

  # Extract fields via python3 → base64-encoded shell vars in temp file
  local _sess_tmp; _sess_tmp=$(mktemp -t mix-$$-sess-load-XXXXXX)
  python3 -c '
import json, sys, time, base64

with open(sys.argv[1]) as f:
    s = json.load(f)

if s.get("version") != 1:
    sys.exit(1)

saved_cwd = s.get("cwd", "")
cur_cwd = sys.argv[2]
if saved_cwd and not (cur_cwd == saved_cwd or cur_cwd.startswith(saved_cwd + "/")):
    sys.exit(2)

ts = s.get("timestamp", 0)
age_h = (time.time() - ts) / 3600
if age_h > 168:
    sys.exit(3)

def b64(v):
    if isinstance(v, dict): v = json.dumps(v)
    if not isinstance(v, str): v = str(v)
    return base64.b64encode(v.encode()).decode()

fields = {
    "env_info": s.get("env_info", ""),
    "git_enabled": s.get("git_enabled", False),
    "git_branch": s.get("git_branch", ""),
    "provider": s.get("provider", "default"),
    "model": s.get("model", ""),
    "base_url": s.get("base_url", ""),
    "caveman_mode": s.get("caveman_mode", "full"),
    "agent_mode": s.get("agent_mode", "fast"),
    "auto_yes": s.get("auto_yes", False),
    "active_skills": s.get("active_skills", ""),
    "file_cache": s.get("file_cache", {}),
    "file_cache_order": s.get("file_cache_order", ""),
    "repo_map": s.get("repo_map", ""),
    "repo_map_mtimes": s.get("repo_map_mtimes", ""),
    "repo_map_time": s.get("repo_map_time", 0),
    "last_input": s.get("last_input", ""),
    "age_h": f"{age_h:.1f}"
}

with open(sys.argv[3], "w") as f:
    for k, v in fields.items():
        f.write(f"_SL_{k}={b64(v)}\n")
' "$_SESSION_FILE" "$WORKDIR" "$_sess_tmp" 2>/dev/null || {
    local _rc=$?
    rm -f "$_sess_tmp"
    [ "$_rc" = "2" ] && echo "  Session from different project, skipping."
    [ "$_rc" = "3" ] && echo "  Session too old (>7d), skipping."
    return 1
  }

  # Source base64 vars and decode
  source "$_sess_tmp" 2>/dev/null
  rm -f "$_sess_tmp"

  _SESSION_RESTORE_ENV=$(printf '%s' "${_SL_env_info:-}" | _mix_base64_decode)
  _SESSION_RESTORE_GIT=$(printf '%s' "${_SL_git_enabled:-}" | _mix_base64_decode)
  _SESSION_RESTORE_BRANCH=$(printf '%s' "${_SL_git_branch:-}" | _mix_base64_decode)
  _SESSION_RESTORE_PROVIDER=$(printf '%s' "${_SL_provider:-}" | _mix_base64_decode)
  _SESSION_RESTORE_MODEL=$(printf '%s' "${_SL_model:-}" | _mix_base64_decode)
  _SESSION_RESTORE_BASE_URL=$(printf '%s' "${_SL_base_url:-}" | _mix_base64_decode)
  _SESSION_RESTORE_CAVEMAN=$(printf '%s' "${_SL_caveman_mode:-}" | _mix_base64_decode)
  _SESSION_RESTORE_MODE=$(printf '%s' "${_SL_agent_mode:-}" | _mix_base64_decode)
  _SESSION_RESTORE_AUTO_YES=$(printf '%s' "${_SL_auto_yes:-}" | _mix_base64_decode)
  _SESSION_RESTORE_SKILLS=$(printf '%s' "${_SL_active_skills:-}" | _mix_base64_decode)
  _SESSION_RESTORE_CACHE=$(printf '%s' "${_SL_file_cache:-}" | _mix_base64_decode)
  _SESSION_RESTORE_CACHE_ORDER=$(printf '%s' "${_SL_file_cache_order:-}" | _mix_base64_decode)
  _SESSION_RESTORE_REPO_MAP=$(printf '%s' "${_SL_repo_map:-}" | _mix_base64_decode)
  _SESSION_RESTORE_REPO_MTIMES=$(printf '%s' "${_SL_repo_map_mtimes:-}" | _mix_base64_decode)
  _SESSION_RESTORE_REPO_TIME=$(printf '%s' "${_SL_repo_map_time:-}" | _mix_base64_decode)
  _SESSION_RESTORE_LAST=$(printf '%s' "${_SL_last_input:-}" | _mix_base64_decode)
  _SESSION_RESTORE_AGE=$(printf '%s' "${_SL_age_h:-}" | _mix_base64_decode)
  _SESSION_AVAILABLE=true; export _SESSION_AVAILABLE

  return 0
}

# Apply saved session — called by /resume
session_apply() {
  [ "$_SESSION_AVAILABLE" != true ] && { echo "  No session to restore."; return 1; }

  # Restore env info
  [ -n "$_SESSION_RESTORE_ENV" ] && ENV_INFO="$_SESSION_RESTORE_ENV"
  [ "$_SESSION_RESTORE_GIT" = "True" ] && GIT_ENABLED=true || GIT_ENABLED=false

  # Restore config
  [ -n "$_SESSION_RESTORE_PROVIDER" ] && PROVIDER="$_SESSION_RESTORE_PROVIDER"
  [ -n "$_SESSION_RESTORE_MODEL" ] && MODEL="$_SESSION_RESTORE_MODEL"
  [ -n "$_SESSION_RESTORE_BASE_URL" ] && BASE_URL="$_SESSION_RESTORE_BASE_URL"
  [ -n "$_SESSION_RESTORE_CAVEMAN" ] && CAVEMAN_MODE="$_SESSION_RESTORE_CAVEMAN"
  [ -n "$_SESSION_RESTORE_MODE" ] && AGENT_MODE="$_SESSION_RESTORE_MODE"
  [ "$_SESSION_RESTORE_AUTO_YES" = "True" ] && AUTO_YES=true || AUTO_YES=false
  [ -n "$_SESSION_RESTORE_SKILLS" ] && ACTIVE_SKILLS="$_SESSION_RESTORE_SKILLS"

  # Restore file cache
  if [ -n "$_SESSION_RESTORE_CACHE" ] && [ "$_SESSION_RESTORE_CACHE" != "{}" ]; then
    _FILE_CACHE="$_SESSION_RESTORE_CACHE"
    _FILE_CACHE_ORDER="$_SESSION_RESTORE_CACHE_ORDER"
    file_cache_validate  # mtime check — removes stale entries
    local _nc
    _nc=$(printf '%s' "$_FILE_CACHE" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || _nc=0
    echo -e "  \033[38;5;82m$I_OK\033[0m File cache restored ($_nc files)"
  fi

  # Restore repo map (TTL still enforced — stale maps rebuilt)
  if [ -n "$_SESSION_RESTORE_REPO_MAP" ]; then
    local _now; _now=$(date +%s 2>/dev/null || echo 0)
    local _age=$(( _now - ${_SESSION_RESTORE_REPO_TIME:-0} ))
    if [ "$_age" -lt "$_REPO_MAP_TTL" ]; then
      _REPO_MAP="$_SESSION_RESTORE_REPO_MAP"
      _REPO_MAP_MTIMES="$_SESSION_RESTORE_REPO_MTIMES"
      _REPO_MAP_TIME="$_SESSION_RESTORE_REPO_TIME"
      echo -e "  \033[38;5;82m$I_OK\033[0m Repo map restored (age: ${_age}s)"
    else
      echo -e "  \033[0;90m  Repo map expired (age: ${_age}s > ${_REPO_MAP_TTL}s), will rebuild\033[0m"
    fi
  fi

  # Re-load provider if needed
  if [ "$PROVIDER" != "default" ]; then
    _load_provider "$PROVIDER" 2>/dev/null || true
  fi

  echo -e "  \033[38;5;82m$I_OK\033[0m Session restored (was ${_SESSION_RESTORE_AGE}h ago)"
  [ -n "$_SESSION_RESTORE_LAST" ] && echo -e "  \033[0;90m  Last task: ${_SESSION_RESTORE_LAST}\033[0m"

  _SESSION_AVAILABLE=false; export _SESSION_AVAILABLE
}

# Clear session file — called by /flush
session_clear() {
  rm -f "$_SESSION_FILE" 2>/dev/null
  _SESSION_AVAILABLE=false; export _SESSION_AVAILABLE
}

# Show startup hint if session available
session_hint() {
  if [ "$_SESSION_AVAILABLE" = true ] && [ "${INTERACTIVE:-false}" = true ]; then
    echo -e "  \033[0;90mPrevious session found (${_SESSION_RESTORE_AGE}h ago). /resume to restore.\033[0m"
  fi
}
