# ─── Config ──────────────────────────────────────────────────────────────────
if [ -t 0 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

API_KEY="${KCONSOLE_API_KEY:-}"
if [ -z "$API_KEY" ]; then
  # Check persistent key file
  _KEY_FILE="${HOME}/.mix/api_key"
  if [ -f "$_KEY_FILE" ]; then
    API_KEY=$(cat "$_KEY_FILE")
  else
    printf "  \033[1;33mAPI key not set.\033[0m Enter key (or set \$KCONSOLE_API_KEY): "
    read -r -s API_KEY < /dev/tty
    printf "\n"
    if [ -z "$API_KEY" ]; then
      echo "  No API key provided. Exiting."
      exit 1
    fi
    printf "  Save key to %s for future sessions? [Y/n] " "$_KEY_FILE"
    read -r _save < /dev/tty
    if [[ "$_save" != [nN]* ]]; then
      mkdir -p "$(dirname "$_KEY_FILE")"
      chmod 700 "$(dirname "$_KEY_FILE")"
      printf '%s' "$API_KEY" > "$_KEY_FILE"
      chmod 600 "$_KEY_FILE"
      echo "  Key saved."
    fi
  fi
fi
BASE_URL="https://ai.koompi.cloud/v1"
MODEL="${AGENT_MODEL:-glm-5}"
HIST_FILE=".mix/history.json"
MAX_TURNS="${MAX_TURNS:-100}"
MAX_HIST_MSGS="${MAX_HIST_MSGS:-200}"  # compact history after this many messages
CTX_TOKENS="${CTX_TOKENS:-131072}"   # model context window size (for % display)
STREAM="${STREAM:-true}"             # stream tokens live
AUTO_YES="${AUTO_YES:-true}"   # yolo mode: auto-confirm all non-blocked commands
# MIX_YOLO=1 env var enables AUTO_YES for non-interactive scripted runs (e.g. /afk apply)
[ "${MIX_YOLO:-}" = "1" ] && AUTO_YES=true
CAVEMAN_MODE="${CAVEMAN_MODE:-full}"  # caveman: off | lite | full | ultra
MAX_FAIL_STREAK="${MAX_FAIL_STREAK:-4}"  # consecutive bash failures before forced fallback hint
FAIL_STREAK=0
AGENT_MODE="${AGENT_MODE:-fast}"  # fast | deep | plan
SANDBOX_ENABLED="${SANDBOX_ENABLED:-false}"  # sandbox mode: requires /sandbox setup first
GIT_ENABLED=false
TEST_CMD=""
ENV_INFO=""
_TOOLS_USED=0
ACTIVE_SKILLS=""
WORKDIR="$(pwd)"

# Token usage tracking
_SESSION_PROMPT_TOKENS=0
_SESSION_COMPLETION_TOKENS=0
_SESSION_API_CALLS=0
_SESSION_CACHE_TOKENS=0

# ─── Provider system ─────────────────────────────────────────────────────────
# Provider = pluggable API backend. Default is openai-compatible (koompi proxy).
# Providers live in src/providers/<name>.sh and override auth/headers/endpoints.
# Activated via: /provider <name>  or  AGENT_PROVIDER=<name>
PROVIDER="${AGENT_PROVIDER:-default}"
PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/providers"
MIX_PROVIDERS_DIR="${HOME}/.mix/providers"  # user-installed providers

# Load provider if set and exists
_load_provider() {
  local name="$1"
  # Check if already loaded (embedded in compiled binary or previously sourced)
  if type "${name}_activate" >/dev/null 2>&1; then
    return 0
  fi
  # Check: built-in files > user-installed files
  local pfile=""
  if [ -f "${PROVIDER_DIR}/${name}.sh" ]; then
    pfile="${PROVIDER_DIR}/${name}.sh"
  elif [ -f "${MIX_PROVIDERS_DIR}/${name}.sh" ]; then
    pfile="${MIX_PROVIDERS_DIR}/${name}.sh"
  fi
  [ -z "$pfile" ] && return 1
  source "$pfile"
  return 0
}

# List available provider names (embedded + file-based)
_list_providers() {
  local -A _seen
  # From embedded/loaded functions (declare -F works in non-interactive)
  while IFS= read -r _line; do
    local _fn="${_line#declare -f }"
    local _pn="${_fn%_activate}"
    [ "$_pn" != "$_fn" ] && [ -n "$_pn" ] && [ -z "${_seen[$_pn]:-}" ] && echo "$_pn" && _seen[$_pn]=1
  done < <(declare -F 2>/dev/null | grep '_activate$')
  # From files
  for f in "$PROVIDER_DIR"/*.sh "$MIX_PROVIDERS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    local _pn
    _pn="$(basename "$f" .sh)"
    [ -z "${_seen[$_pn]:-}" ] && echo "$_pn" && _seen[$_pn]=1
  done
}

# ─── Persist/restore provider+model defaults ────────────────────────────────
_MIX_DEFAULTS_FILE="${HOME}/.mix/defaults"

_mix_save_defaults() {
  mkdir -p "${HOME}/.mix"
  # Save current config + remember the model specifically for this provider
  local _tmp_file; _tmp_file=$(mktemp)
  [ -f "$_MIX_DEFAULTS_FILE" ] && cp "$_MIX_DEFAULTS_FILE" "$_tmp_file" || touch "$_tmp_file"
  
  # Remove current general keys and this provider's model key
  sed -i '/^PROVIDER=/d' "$_tmp_file"
  sed -i '/^MODEL=/d' "$_tmp_file"
  sed -i '/^BASE_URL=/d' "$_tmp_file"
  sed -i "/^MODEL_${PROVIDER}=/d" "$_tmp_file"
  
  # Append updated values
  printf 'PROVIDER=%s\nMODEL=%s\nBASE_URL=%s\nMODEL_%s=%s\n' \
    "$PROVIDER" "$MODEL" "$BASE_URL" "$PROVIDER" "$MODEL" >> "$_tmp_file"
  
  mv "$_tmp_file" "$_MIX_DEFAULTS_FILE"
}

# Load saved defaults (overridden by env vars if set)
if [ -f "$_MIX_DEFAULTS_FILE" ] && [ -z "${AGENT_PROVIDER:-}" ]; then
  _saved_provider=$(grep '^PROVIDER=' "$_MIX_DEFAULTS_FILE" | cut -d= -f2-)
  _saved_model=$(grep '^MODEL=' "$_MIX_DEFAULTS_FILE" | cut -d= -f2-)
  _saved_url=$(grep '^BASE_URL=' "$_MIX_DEFAULTS_FILE" | cut -d= -f2-)
  [ -n "$_saved_provider" ] && PROVIDER="$_saved_provider"
  [ -n "$_saved_model" ]   && MODEL="$_saved_model"
  [ -n "$_saved_url" ]     && BASE_URL="$_saved_url"
fi

# Auto-load provider at startup if AGENT_PROVIDER is set
if [ "$PROVIDER" != "default" ]; then
  if _load_provider "$PROVIDER"; then
    # If provider exports an _activate function, call it (non-interactive mode)
    if type "${PROVIDER}_activate" >/dev/null 2>&1; then
      ${PROVIDER}_activate 2>/dev/null || true
    fi
  fi
fi

