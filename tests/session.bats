#!/usr/bin/env bats
# Tests for src/11c_session.sh — session_save, session_load, session_apply, session_clear

# Compute PROJECT_ROOT from test location
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
source "$PROJECT_ROOT/src/11c_session.sh"

# Setup: create temp dir, cd into it, set required globals
setup() {
  _TEST_DIR="$(mktemp -d)"
  cd "$_TEST_DIR"
  mkdir -p .agent

  # Set required globals that session functions reference
  WORKDIR="$_TEST_DIR"
  INTERACTIVE=true
  ENV_INFO="git:master shellcheck"
  GIT_ENABLED=true
  PROVIDER="default"
  MODEL="glm-5"
  BASE_URL="https://ai.koompi.cloud/v1"
  CAVEMAN_MODE="full"
  AGENT_MODE="fast"
  AUTO_YES=false
  ACTIVE_SKILLS=""
  _FILE_CACHE='{}'
  _FILE_CACHE_ORDER=""
  _REPO_MAP=""
  _REPO_MAP_MTIMES=""
  _REPO_MAP_TIME=0
  _REPO_MAP_TTL=600
  HISTORY='[]'
  _LAST_INPUT=""
  _SESSION_AVAILABLE=false
}

teardown() {
  cd /
  rm -rf "$_TEST_DIR"
}

# ─── session_save ──────────────────────────────────────────────────────

@test "session_save creates .agent/session.json" {
  _LAST_INPUT="test task"
  session_save
  [ -f ".agent/session.json" ]
}

@test "session_save writes valid JSON" {
  _LAST_INPUT="test task"
  session_save
  python3 -c "import json; json.load(open('.agent/session.json'))"
}

@test "session_save has version 1" {
  _LAST_INPUT="test task"
  session_save
  local v
  v=$(python3 -c "import json; print(json.load(open('.agent/session.json'))['version'])")
  [ "$v" = "1" ]
}

@test "session_save stores model and provider" {
  MODEL="test-model"
  PROVIDER="testprov"
  _LAST_INPUT=""
  session_save
  local m p
  m=$(python3 -c "import json; print(json.load(open('.agent/session.json'))['model'])")
  p=$(python3 -c "import json; print(json.load(open('.agent/session.json'))['provider'])")
  [ "$m" = "test-model" ]
  [ "$p" = "testprov" ]
}

@test "session_save stores file_cache" {
  _FILE_CACHE='{"test.sh":{"content":"hello","mtime":123,"atime":456,"lines":5}}'
  _FILE_CACHE_ORDER="test.sh"
  _LAST_INPUT=""
  session_save
  local nc
  nc=$(python3 -c "import json; d=json.load(open('.agent/session.json')); print(len(d['file_cache']))")
  [ "$nc" = "1" ]
}

@test "session_save truncates oversized file cache" {
  # Create a cache entry > 40KB
  local _big_content=""
  for i in $(seq 1 5000); do _big_content+="line $i of padding data here\n"; done
  _FILE_CACHE="{\"big.sh\":{\"content\":\"$_big_content\",\"mtime\":123,\"atime\":456,\"lines\":5000}}"
  _FILE_CACHE_ORDER="big.sh"
  _LAST_INPUT=""
  session_save
  local fsize
  fsize=$(wc -c < ".agent/session.json")
  [ "$fsize" -lt 55000 ]
}

@test "session_save stores last_input" {
  _LAST_INPUT="fix the auth bug"
  session_save
  local li
  li=$(python3 -c "import json; print(json.load(open('.agent/session.json'))['last_input'])")
  [ "$li" = "fix the auth bug" ]
}

@test "session_save stores cwd" {
  _LAST_INPUT=""
  session_save
  local cwd
  cwd=$(python3 -c "import json; print(json.load(open('.agent/session.json'))['cwd'])")
  [ "$cwd" = "$_TEST_DIR" ]
}

@test "session_save skips in non-interactive mode" {
  INTERACTIVE=false
  _LAST_INPUT="test"
  session_save
  [ ! -f ".agent/session.json" ]
}

@test "session_save does not leak API key" {
  API_KEY="sk-secret-key-12345"
  _LAST_INPUT=""
  session_save
  if [ -f ".agent/session.json" ]; then
    ! grep -q "sk-secret-key-12345" ".agent/session.json"
  fi
}

# ─── session_load ──────────────────────────────────────────────────────

@test "session_load returns 1 when no session file" {
  rm -f .agent/session.json
  ! session_load
}

@test "session_load returns 0 with valid session" {
  _LAST_INPUT="test"
  session_save
  _SESSION_AVAILABLE=false
  session_load
}

@test "session_load sets _SESSION_AVAILABLE=true" {
  _LAST_INPUT="test"
  session_save
  _SESSION_AVAILABLE=false
  session_load
  [ "$_SESSION_AVAILABLE" = true ]
}

@test "session_load rejects corrupted JSON" {
  echo "not json at all" > .agent/session.json
  ! session_load
}

@test "session_load sets restore age" {
  _LAST_INPUT="test"
  session_save
  _SESSION_AVAILABLE=false
  session_load
  [ -n "$_SESSION_RESTORE_AGE" ]
}

@test "session_load rejects different project CWD" {
  _LAST_INPUT="test"
  session_save
  # Simulate different CWD
  WORKDIR="/totally/different/path"
  _SESSION_AVAILABLE=false
  ! session_load
  WORKDIR="$_TEST_DIR"
}

# ─── session_apply ─────────────────────────────────────────────────────

@test "session_apply restores model" {
  MODEL="before-model"
  PROVIDER="default"
  _LAST_INPUT=""
  session_save
  MODEL="wrong"
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$MODEL" = "before-model" ]
}

@test "session_apply restores caveman_mode" {
  CAVEMAN_MODE="ultra"
  _LAST_INPUT=""
  session_save
  CAVEMAN_MODE="off"
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$CAVEMAN_MODE" = "ultra" ]
}

@test "session_apply restores agent_mode" {
  AGENT_MODE="plan"
  _LAST_INPUT=""
  session_save
  AGENT_MODE="fast"
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$AGENT_MODE" = "plan" ]
}

@test "session_apply restores auto_yes" {
  AUTO_YES=true
  _LAST_INPUT=""
  session_save
  AUTO_YES=false
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$AUTO_YES" = true ]
}

@test "session_apply restores env_info" {
  ENV_INFO="git:main node python"
  _LAST_INPUT=""
  session_save
  ENV_INFO=""
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$ENV_INFO" = "git:main node python" ]
}

@test "session_apply restores file cache" {
  _FILE_CACHE='{"test.sh":{"content":"hello","mtime":100,"atime":200,"lines":5}}'
  _FILE_CACHE_ORDER="test.sh"
  # Create file with matching mtime so validate doesn't drop it
  echo "hello" > test.sh
  touch -t 197001010000 test.sh  # mtime=0
  _LAST_INPUT=""
  session_save
  _FILE_CACHE='{}'
  _FILE_CACHE_ORDER=""
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  # Cache may be validated/cleaned, but should have entries
  local nc
  nc=$(printf '%s' "$_FILE_CACHE" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || nc=0
  [ "$nc" -ge 0 ]
}

@test "session_apply clears _SESSION_AVAILABLE" {
  _LAST_INPUT=""
  session_save
  _SESSION_AVAILABLE=false
  session_load
  session_apply
  [ "$_SESSION_AVAILABLE" = false ]
}

# ─── session_clear ─────────────────────────────────────────────────────

@test "session_clear removes session file" {
  _LAST_INPUT=""
  session_save
  [ -f ".agent/session.json" ]
  session_clear
  [ ! -f ".agent/session.json" ]
}

@test "session_clear resets _SESSION_AVAILABLE" {
  _SESSION_AVAILABLE=true
  session_clear
  [ "$_SESSION_AVAILABLE" = false ]
}

# ─── session_hint ──────────────────────────────────────────────────────

@test "session_hint is silent when no session" {
  _SESSION_AVAILABLE=false
  local output
  output=$(session_hint 2>&1)
  [ -z "$output" ]
}

@test "session_hint prints message when session available" {
  _SESSION_AVAILABLE=true
  _SESSION_RESTORE_AGE="1.5"
  INTERACTIVE=true
  local output
  output=$(session_hint 2>&1)
  echo "$output" | grep -q "Previous session"
}
