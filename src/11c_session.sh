# ─── Session Persistence (/resume) ───────────────────────────────────────────
# Saves session state on exit, restores on /resume.
# File cache, repo map, env info, config — all survive restart.
# Session file: .agent/session.json (gitignored, < 50KB)

_SESSION_FILE=".agent/session.json"
_SESSION_VERSION=1

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
# Keep only the 4 most recent entries
order = sys.argv[1].split()
keep = order[-4:] if len(order) > 4 else order
filtered = {k: v for k, v in cache.items() if k in keep}
print(json.dumps(filtered))
' "$_FILE_CACHE_ORDER" 2>/dev/null) || _save_cache='{}'
    # Rebuild order to match
    local _new_order=""
    for _fp in $_FILE_CACHE_ORDER; do
      if printf '%s' "$_save_cache" | grep -qF "\"$_fp\""; then
        _new_order="${_new_order:+$_new_order }$_fp"
      fi
    done
    _FILE_CACHE_ORDER="$_new_order"
  fi

  # Get git branch
  local _branch=""
  [ "$GIT_ENABLED" = true ] && _branch=$(git -C "$WORKDIR" branch --show-current 2>/dev/null || echo "?")

  # Build session JSON via python3
  local _sess_tmp; _sess_tmp=$(mktemp -t mix-session-XXXXXX)
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

  # Atomic move
  mkdir -p .agent 2>/dev/null || true
  mv "$_sess_tmp" "$_SESSION_FILE" 2>/dev/null || rm -f "$_sess_tmp"
}

# Load session from disk — called at startup
session_load() {
  [ ! -f "$_SESSION_FILE" ] && return 1

  # Validate JSON
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_SESSION_FILE" 2>/dev/null || {
    echo "  Warning: session file corrupted, skipping."
    return 1
  }

  # Read session into variables via python3
  local _out
  _out=$(python3 -c '
import json, sys, os, time

with open(sys.argv[1]) as f:
    s = json.load(f)

# Version check
if s.get("version") != 1:
    sys.exit(1)

# CWD check — only restore if same project (or subdirectory)
saved_cwd = s.get("cwd", "")
cur_cwd = sys.argv[2]
if saved_cwd and not (cur_cwd == saved_cwd or cur_cwd.startswith(saved_cwd + "/")):
    sys.exit(2)  # different project

# Age check
ts = s.get("timestamp", 0)
age_h = (time.time() - ts) / 3600
if age_h > 168:  # 7 days
    sys.exit(3)  # too old

# Output restorable fields as tab-separated
fc = s.get("file_cache", {})
if isinstance(fc, dict):
    fc = json.dumps(fc)
print("\t".join([
    s.get("env_info", ""),
    str(s.get("git_enabled", False)),
    s.get("git_branch", ""),
    s.get("provider", "default"),
    s.get("model", ""),
    s.get("base_url", ""),
    s.get("caveman_mode", "full"),
    s.get("agent_mode", "fast"),
    str(s.get("auto_yes", False)),
    s.get("active_skills", ""),
    fc,
    s.get("file_cache_order", ""),
    s.get("repo_map", ""),
    s.get("repo_map_mtimes", ""),
    str(s.get("repo_map_time", 0)),
    s.get("last_input", ""),
    f"{age_h:.1f}"
]))
' "$_SESSION_FILE" "$WORKDIR" 2>/dev/null) || {
    local _rc=$?
    [ "$_rc" = "2" ] && echo "  Session from different project, skipping."
    [ "$_rc" = "3" ] && echo "  Session too old (>7d), skipping."
    return 1
  }

  # Parse tab-separated output
  IFS=$'\t' read -r _s_env_info _s_git_enabled _s_git_branch _s_provider _s_model _s_base_url \
    _s_caveman _s_agent_mode _s_auto_yes _s_skills _s_file_cache _s_file_cache_order \
    _s_repo_map _s_repo_map_mtimes _s_repo_map_time _s_last_input _s_age_h <<< "$_out"

  # Store for lazy restore (don't apply until /resume)
  _SESSION_RESTORE_ENV="$_s_env_info"
  _SESSION_RESTORE_GIT="$_s_git_enabled"
  _SESSION_RESTORE_BRANCH="$_s_git_branch"
  _SESSION_RESTORE_PROVIDER="$_s_provider"
  _SESSION_RESTORE_MODEL="$_s_model"
  _SESSION_RESTORE_BASE_URL="$_s_base_url"
  _SESSION_RESTORE_CAVEMAN="$_s_caveman"
  _SESSION_RESTORE_MODE="$_s_agent_mode"
  _SESSION_RESTORE_AUTO_YES="$_s_auto_yes"
  _SESSION_RESTORE_SKILLS="$_s_skills"
  _SESSION_RESTORE_CACHE="$_s_file_cache"
  _SESSION_RESTORE_CACHE_ORDER="$_s_file_cache_order"
  _SESSION_RESTORE_REPO_MAP="$_s_repo_map"
  _SESSION_RESTORE_REPO_MTIMES="$_s_repo_map_mtimes"
  _SESSION_RESTORE_REPO_TIME="$_s_repo_map_time"
  _SESSION_RESTORE_LAST="$_s_last_input"
  _SESSION_RESTORE_AGE="$_s_age_h"
  _SESSION_AVAILABLE=true

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
    echo -e "  \033[38;5;82m✓\033[0m File cache restored ($_nc files)"
  fi

  # Restore repo map (TTL still enforced — stale maps rebuilt)
  if [ -n "$_SESSION_RESTORE_REPO_MAP" ]; then
    local _now; _now=$(date +%s 2>/dev/null || echo 0)
    local _age=$(( _now - ${_SESSION_RESTORE_REPO_TIME:-0} ))
    if [ "$_age" -lt "$_REPO_MAP_TTL" ]; then
      _REPO_MAP="$_SESSION_RESTORE_REPO_MAP"
      _REPO_MAP_MTIMES="$_SESSION_RESTORE_REPO_MTIMES"
      _REPO_MAP_TIME="$_SESSION_RESTORE_REPO_TIME"
      echo -e "  \033[38;5;82m✓\033[0m Repo map restored (age: ${_age}s)"
    else
      echo -e "  \033[0;90m  Repo map expired (age: ${_age}s > ${_REPO_MAP_TTL}s), will rebuild\033[0m"
    fi
  fi

  # Re-load provider if needed
  if [ "$PROVIDER" != "default" ]; then
    _load_provider "$PROVIDER" 2>/dev/null || true
  fi

  echo -e "  \033[38;5;82m✓\033[0m Session restored (was ${_SESSION_RESTORE_AGE}h ago)"
  [ -n "$_SESSION_RESTORE_LAST" ] && echo -e "  \033[0;90m  Last task: ${_SESSION_RESTORE_LAST}\033[0m"

  # Clear restore state
  _SESSION_AVAILABLE=false
}

# Clear session file — called by /flush
session_clear() {
  rm -f "$_SESSION_FILE" 2>/dev/null
  _SESSION_AVAILABLE=false
}

# Show startup hint if session available
session_hint() {
  if [ "$_SESSION_AVAILABLE" = true ] && [ "$INTERACTIVE" = true ]; then
    echo -e "  \033[0;90mPrevious session found (${_SESSION_RESTORE_AGE}h ago). /resume to restore.\033[0m"
  fi
}
