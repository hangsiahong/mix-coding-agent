# ─── Config ──────────────────────────────────────────────────────────────────
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
HIST_FILE=".agent_history.json"
MAX_TURNS="${MAX_TURNS:-50}"
MAX_HIST_MSGS="${MAX_HIST_MSGS:-60}"  # compact history after this many messages
CTX_TOKENS="${CTX_TOKENS:-131072}"   # model context window size (for % display)
STREAM="${STREAM:-true}"             # stream tokens live
AUTO_YES="${AUTO_YES:-true}"   # yolo mode: auto-confirm all non-blocked commands
CAVEMAN_MODE="${CAVEMAN_MODE:-full}"  # caveman: off | lite | full | ultra
MAX_FAIL_STREAK="${MAX_FAIL_STREAK:-4}"  # consecutive bash failures before forced fallback hint
FAIL_STREAK=0
AGENT_MODE="${AGENT_MODE:-fast}"  # fast | deep | plan
GIT_ENABLED=false
TEST_CMD=""
ENV_INFO=""
_TOOLS_USED=0
ACTIVE_SKILLS=""
WORKDIR="$(pwd)"

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
  # Check: built-in > user-installed
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

# Auto-load provider at startup if AGENT_PROVIDER is set
if [ "$PROVIDER" != "default" ]; then
  if _load_provider "$PROVIDER"; then
    # If provider exports an _activate function, call it (non-interactive mode)
    if type "${PROVIDER}_activate" >/dev/null 2>&1; then
      ${PROVIDER}_activate 2>/dev/null || true
    fi
  fi
fi

