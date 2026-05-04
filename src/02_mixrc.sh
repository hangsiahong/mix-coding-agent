# ─── Project Overrides (.mixrc) ──────────────────────────────────────────────
# Loads per-project settings from .mixrc file in WORKDIR.
# Priority: env vars > .mixrc > ~/.mix/defaults
# .mixrc is a simple KEY=VALUE file (shell-sourceable, no code execution).

_MIXRC_FILE="${WORKDIR}/.mixrc"
_MIXRC_LOADED=false

_mixrc_load() {
  # Walk up from WORKDIR to find .mixrc
  local _dir="$WORKDIR"
  local _found=""
  while [ "$_dir" != "/" ]; do
    if [ -f "$_dir/.mixrc" ]; then
      _found="$_dir/.mixrc"
      break
    fi
    _dir="$(dirname "$_dir")"
  done

  [ -z "$_found" ] && return

  # Whitelist of allowed keys (security — no arbitrary shell execution)
  local -A _allowed
  _allowed[MODEL]=1
  _allowed[BASE_URL]=1
  _allowed[PROVIDER]=1
  _allowed[CAVEMAN_MODE]=1
  _allowed[AGENT_MODE]=1
  _allowed[AUTO_YES]=1
  _allowed[STREAM]=1
  _allowed[MAX_TURNS]=1
  _allowed[MAX_HIST_MSGS]=1
  _allowed[CTX_TOKENS]=1
  _allowed[VERIFY_CMD]=1
  _allowed[AUTO_VERIFY]=1
  _allowed[MAX_FAIL_STREAK]=1
  _allowed[TEST_CMD]=1
  _allowed[REPO_MAP_TTL]=1
  _allowed[GIT_ENABLED]=1

  local _key _val _line _count=0
  while IFS='=' read -r _key _val || [ -n "$_key" ]; do
    # Skip comments and blank lines
    [[ "$_key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$_key" ]] && continue
    # Trim whitespace
    _key="${_key//[[:space:]]/}"
    # Validate key is in whitelist
    [ -z "${_allowed[$_key]:-}" ] && continue
    # Strip surrounding quotes from value
    _val="${_val#\"}" ; _val="${_val%\"}"
    _val="${_val#\'}" ; _val="${_val%\'}"
    # Only apply if env var NOT already set (env wins over .mixrc)
    case "$_key" in
      MODEL)         [ -z "${AGENT_MODEL:-}" ]         && MODEL="$_val" ;;
      BASE_URL)      [ -z "${AGENT_BASE_URL:-}" ]      && BASE_URL="$_val" ;;
      PROVIDER)      [ -z "${AGENT_PROVIDER:-}" ]       && PROVIDER="$_val" ;;
      CAVEMAN_MODE)  [ -z "${CAVEMAN_MODE:-}" ]         && CAVEMAN_MODE="$_val" ;;
      AGENT_MODE)    [ -z "${AGENT_MODE:-}" ]           && AGENT_MODE="$_val" ;;
      AUTO_YES)      [ -z "${AUTO_YES:-}" ]             && AUTO_YES="$_val" ;;
      STREAM)        [ -z "${STREAM:-}" ]               && STREAM="$_val" ;;
      MAX_TURNS)     [ -z "${MAX_TURNS:-}" ]            && MAX_TURNS="$_val" ;;
      MAX_HIST_MSGS) [ -z "${MAX_HIST_MSGS:-}" ]        && MAX_HIST_MSGS="$_val" ;;
      CTX_TOKENS)    [ -z "${CTX_TOKENS:-}" ]           && CTX_TOKENS="$_val" ;;
      VERIFY_CMD)    [ -z "${VERIFY_CMD:-}" ]           && VERIFY_CMD="$_val" ;;
      AUTO_VERIFY)   [ -z "${AUTO_VERIFY:-}" ]          && AUTO_VERIFY="$_val" ;;
      MAX_FAIL_STREAK) [ -z "${MAX_FAIL_STREAK:-}" ]    && MAX_FAIL_STREAK="$_val" ;;
      TEST_CMD)      [ -z "${TEST_CMD:-}" ]             && TEST_CMD="$_val" ;;
      REPO_MAP_TTL)  [ -z "${REPO_MAP_TTL:-}" ]         && _REPO_MAP_TTL="$_val" ;;
      GIT_ENABLED)   [ -z "${GIT_ENABLED:-}" ]          && GIT_ENABLED="$_val" ;;
    esac
    _count=$((_count + 1))
  done < "$_found"

  if [ "$_count" -gt 0 ]; then
    _MIXRC_FILE="$_found"
    _MIXRC_LOADED=true
  fi
}

_mixrc_show() {
  if [ "$_MIXRC_LOADED" = true ]; then
    echo -e "  \033[38;5;82m●\033[0m Loaded from \033[1;37m$_MIXRC_FILE\033[0m"
    local _key _val
    while IFS='=' read -r _key _val || [ -n "$_key" ]; do
      [[ "$_key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$_key" ]] && continue
      _key="${_key//[[:space:]]/}"
      _val="${_val#\"}" ; _val="${_val%\"}"
      _val="${_val#\'}" ; _val="${_val%\'}"
      echo -e "    \033[0;90m$_key\033[0m = \033[1;37m$_val\033[0m"
    done < "$_MIXRC_FILE"
  else
    echo -e "  \033[0;90mNo .mixrc found (checked WORKDIR and parents)\033[0m"
    echo -e "  Create .mixrc with KEY=VALUE pairs. Allowed keys:"
    echo "    MODEL  BASE_URL  PROVIDER  CAVEMAN_MODE  AGENT_MODE"
    echo "    AUTO_YES  STREAM  MAX_TURNS  MAX_HIST_MSGS  CTX_TOKENS"
    echo "    AUTO_VERIFY  VERIFY_CMD  MAX_FAIL_STREAK  TEST_CMD"
    echo "    REPO_MAP_TTL  GIT_ENABLED"
  fi
}

# Load on source
_mixrc_load
