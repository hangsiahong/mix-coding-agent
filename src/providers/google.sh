# ─── Provider: Google (AI Studio + Vertex AI) ────────────────────────────────
# Supports two Google API surfaces, both OpenAI-compatible:
#
# 1. Google AI Studio (Gemini API) — simple, API key only
#    Endpoint: https://generativelanguage.googleapis.com/v1beta/openai
#    Auth: static API key from https://aistudio.google.com/apikey
#    Models: gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash
#
# 2. Google Vertex AI — enterprise, gcloud CLI auth
#    Endpoint: https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/{REGION}/endpoints/openapi
#    Auth: gcloud auth print-access-token (short-lived, auto-refreshes)
#    Same models + enterprise ones
#
# Config:
#   PROVIDER=google
#   MODEL=gemini-2.5-pro
#
# Files:
#   ~/.mix/google_provider   — stores: mode=studio|vertex, project_id, region
#   ~/.mix/google_api_key    — Studio API key (optional, can use env var)
#   /tmp/mix-google-token    — cached Vertex access token (auto-refreshes)

_GOOGLE_CONFIG_FILE="${HOME}/.mix/google_provider"
_GOOGLE_KEY_FILE="${HOME}/.mix/google_api_key"
_GOOGLE_TOKEN_CACHE="/tmp/mix-google-access-token"

# Known models (hardcoded — stable, small list)
_GOOGLE_MODELS=(
  "gemini-2.5-pro"
  "gemini-2.5-flash"
  "gemini-2.5-flash-lite"
  "gemini-2.0-flash"
  "gemini-2.0-flash-lite"
  "gemini-1.5-pro"
  "gemini-1.5-flash"
)

# ─── Activate: read config, set BASE_URL + auth ────────────────────────────
google_activate() {
  # Determine mode: env override > config file > auto-detect
  local mode="${GOOGLE_MODE:-}"
  local project_id="${GOOGLE_PROJECT:-}"
  local region="${GOOGLE_REGION:-us-central1}"

  if [ -z "$mode" ] && [ -f "$_GOOGLE_CONFIG_FILE" ]; then
    mode=$(grep '^mode=' "$_GOOGLE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
    project_id=$(grep '^project_id=' "$_GOOGLE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
    region=$(grep '^region=' "$_GOOGLE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-)
    [ -z "$region" ] && region="us-central1"
  fi

  # Auto-detect: prefer Studio if key available, else Vertex if gcloud available
  if [ -z "$mode" ]; then
    if [ -n "${GOOGLE_API_KEY:-}" ] || [ -f "$_GOOGLE_KEY_FILE" ]; then
      mode="studio"
    elif command -v gcloud >/dev/null 2>&1; then
      mode="vertex"
    else
      echo -e "  \033[1;33mGoogle provider: no credentials found.\033[0m"
      echo "  Run: /provider google login"
      return 1
    fi
  fi

  if [ "$mode" = "studio" ]; then
    BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"
    local api_key="${GOOGLE_API_KEY:-}"
    if [ -z "$api_key" ] && [ -f "$_GOOGLE_KEY_FILE" ]; then
      api_key=$(cat "$_GOOGLE_KEY_FILE")
    fi
    if [ -z "$api_key" ]; then
      echo -e "  \033[1;33mNo Google API key. Run: /provider google login\033[0m"
      return 1
    fi
    API_KEY="$api_key"
    PROVIDER="google"
    [ -z "${MODEL:-}" ] && MODEL="gemini-2.5-pro"
    echo -e "  \033[38;5;82m✓\033[0m Google AI Studio activated"
    echo "  Model: $MODEL | Endpoint: generativelanguage.googleapis.com"
    _mix_save_defaults
    return 0
  elif [ "$mode" = "vertex" ]; then
    if [ -z "$project_id" ]; then
      echo -e "  \033[1;33mNo Google Cloud project ID set.\033[0m"
      echo "  Run: /provider google login"
      return 1
    fi
    BASE_URL="https://${region}-aiplatform.googleapis.com/v1/projects/${project_id}/locations/${region}/endpoints/openapi"
    PROVIDER="google"
    [ -z "${MODEL:-}" ] && MODEL="gemini-2.5-pro"
    # Vertex OpenAI-compat needs 'google/' prefix in model field
    _GOOGLE_VERTEX_MODEL_PREFIX="google/"
    # Store API key for Vertex (used via x-goog-api-key header)
    local api_key="${GOOGLE_API_KEY:-}"
    if [ -z "$api_key" ] && [ -f "$_GOOGLE_KEY_FILE" ]; then
      api_key=$(cat "$_GOOGLE_KEY_FILE")
    fi
    API_KEY="$api_key"
    echo -e "  \033[38;5;82m✓\033[0m Google Vertex AI activated"
    echo "  Model: $MODEL | Project: $project_id | Region: $region"
    _mix_save_defaults
    return 0
  else
    echo -e "  \033[1;31mUnknown Google mode: $mode. Use 'studio' or 'vertex'.\033[0m"
    return 1
  fi
}

# ─── Login: interactive setup ───────────────────────────────────────────────
google_login() {
  echo -e "  \033[1;37mGoogle Provider Setup\033[0m"
  echo ""
  echo "  Choose authentication method:"
  echo "    1) AI Studio — API key (free, personal)"
  echo "    2) Vertex AI — gcloud + project (enterprise)"
  echo ""

  local choice
  printf "  Choice [1/2]: "
  read -r choice < /dev/tty

  if [ "$choice" = "1" ]; then
    _google_login_studio
  elif [ "$choice" = "2" ]; then
    _google_login_vertex
  else
    echo "  Cancelled."
    return 1
  fi
}

_google_login_studio() {
  echo ""
  echo -e "  \033[1;37mGoogle AI Studio — API Key\033[0m"
  echo "  Get your key at: \033[4mhttps://aistudio.google.com/apikey\033[0m"
  echo ""

  local api_key="${GOOGLE_API_KEY:-}"
  if [ -n "$api_key" ]; then
    echo -e "  \033[0;90mGOOGLE_API_KEY env var detected.\033[0m"
    printf "  Use it? [Y/n]: "
    read -r use_env < /dev/tty
    if [[ "$use_env" != [nN]* ]]; then
      _google_save_config "studio"
      echo -e "  \033[38;5;82m✓\033[0m Using GOOGLE_API_KEY env var."
      return 0
    fi
  fi

  printf "  Paste API key: "
  read -r -s api_key < /dev/tty
  printf "\n"

  if [ -z "$api_key" ]; then
    echo -e "  \033[1;31mNo key provided.\033[0m"
    return 1
  fi

  # Validate key with a quick test call
  echo "  Validating key..."
  local test_resp
  test_resp=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://generativelanguage.googleapis.com/v1beta/models?key=${api_key}" 2>/dev/null) || true

  if [ "$test_resp" = "200" ]; then
    mkdir -p "$(dirname "$_GOOGLE_KEY_FILE")"
    chmod 700 "$(dirname "$_GOOGLE_KEY_FILE")"
    printf '%s' "$api_key" > "$_GOOGLE_KEY_FILE"
    chmod 600 "$_GOOGLE_KEY_FILE"
    _google_save_config "studio"
    echo -e "  \033[38;5;82m✓\033[0m API key validated and saved."
  elif [ "$test_resp" = "400" ] || [ "$test_resp" = "403" ]; then
    echo -e "  \033[1;31m✗ Invalid API key (HTTP $test_resp).\033[0m"
    return 1
  else
    echo -e "  \033[1;33m⚠ Could not validate (HTTP $test_resp). Saving anyway.\033[0m"
    mkdir -p "$(dirname "$_GOOGLE_KEY_FILE")"
    chmod 700 "$(dirname "$_GOOGLE_KEY_FILE")"
    printf '%s' "$api_key" > "$_GOOGLE_KEY_FILE"
    chmod 600 "$_GOOGLE_KEY_FILE"
    _google_save_config "studio"
  fi
}

_google_login_vertex() {
  echo ""
  echo -e "  \033[1;37mGoogle Vertex AI — gcloud CLI\033[0m"

  # Check gcloud
  if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "  \033[1;31m✗ gcloud CLI not found.\033[0m"
    echo "  Install: https://cloud.google.com/sdk/docs/install"
    return 1
  fi

  # Check auth
  local account
  account=$(gcloud config get-value account 2>/dev/null) || true
  if [ -z "$account" ]; then
    echo "  No gcloud account configured. Running gcloud auth login..."
    gcloud auth login --no-launch-browser
    account=$(gcloud config get-value account 2>/dev/null) || true
    if [ -z "$account" ]; then
      echo -e "  \033[1;31m✗ Login failed.\033[0m"
      return 1
    fi
  fi
  echo -e "  Account: \033[38;5;82m$account\033[0m"

  # Get project
  local project_id="${GOOGLE_PROJECT:-}"
  if [ -z "$project_id" ]; then
    project_id=$(gcloud config get-value project 2>/dev/null) || true
  fi
  if [ -n "$project_id" ]; then
    printf "  Project ID [%s]: " "$project_id"
  else
    printf "  Project ID: "
  fi
  read -r project_id_input < /dev/tty
  [ -n "$project_id_input" ] && project_id="$project_id_input"

  if [ -z "$project_id" ]; then
    echo -e "  \033[1;31m✗ Project ID required.\033[0m"
    return 1
  fi

  # Get region
  local region="${GOOGLE_REGION:-us-central1}"
  printf "  Region [%s]: " "$region"
  read -r region_input < /dev/tty
  [ -n "$region_input" ] && region="$region_input"

  # Enable Vertex AI API if not enabled
  echo "  Checking Vertex AI API..."
  local api_enabled
  api_enabled=$(gcloud services list --enabled --project="$project_id" \
    --filter="name:aiplatform.googleapis.com" --format="value(name)" 2>/dev/null) || true
  if [ -z "$api_enabled" ]; then
    echo "  Enabling Vertex AI API (one-time)..."
    gcloud services enable aiplatform.googleapis.com --project="$project_id" 2>/dev/null || {
      echo -e "  \033[1;33m⚠ Could not auto-enable API. Enable manually:\033[0m"
      echo "  gcloud services enable aiplatform.googleapis.com --project=$project_id"
    }
  fi

  # Test token generation
  echo "  Testing access token..."
  local test_token
  test_token=$(gcloud auth print-access-token 2>/dev/null) || true
  if [ -z "$test_token" ]; then
    echo -e "  \033[1;31m✗ Could not generate access token.\033[0m"
    echo "  Try: gcloud auth login"
    return 1
  fi

  _google_save_config "vertex" "$project_id" "$region"
  echo -e "  \033[38;5;82m✓\033[0m Vertex AI configured."
  echo "  Project: $project_id | Region: $region"
}

_google_save_config() {
  local mode="$1"
  local project_id="${2:-}"
  local region="${3:-us-central1}"
  mkdir -p "$(dirname "$_GOOGLE_CONFIG_FILE")"
  printf 'mode=%s\nproject_id=%s\nregion=%s\n' "$mode" "$project_id" "$region" > "$_GOOGLE_CONFIG_FILE"
  chmod 600 "$_GOOGLE_CONFIG_FILE"
}

# ─── Get API key (called on every API request) ─────────────────────────────
google_get_api_key() {
  local mode
  mode=$(grep '^mode=' "$_GOOGLE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-) || true

  if [ "$mode" = "studio" ]; then
    # Studio: static API key
    local key="${GOOGLE_API_KEY:-}"
    if [ -z "$key" ] && [ -f "$_GOOGLE_KEY_FILE" ]; then
      key=$(cat "$_GOOGLE_KEY_FILE")
    fi
    if [ -z "$key" ]; then
      echo -e "  \033[1;33mNo Google API key. Run: /provider google login\033[0m" >&2
      return 1
    fi
    printf '%s' "$key"
    return 0
  elif [ "$mode" = "vertex" ]; then
    # Vertex: use API key (same key, just different header delivery)
    local key="${GOOGLE_API_KEY:-}"
    if [ -z "$key" ] && [ -f "$_GOOGLE_KEY_FILE" ]; then
      key=$(cat "$_GOOGLE_KEY_FILE")
    fi
    if [ -z "$key" ]; then
      echo -e "  \033[1;33mNo Google API key. Run: /provider google login\033[0m" >&2
      return 1
    fi
    printf '%s' "$key"
    return 0
  else
    echo -e "  \033[1;33mGoogle provider not configured. Run: /provider google login\033[0m" >&2
    return 1
  fi
}

# ─── Vertex token: cached + auto-refresh ────────────────────────────────────
_google_vertex_token() {
  # Check cache (tokens valid ~1hr, refresh at 50min)
  if [ -f "$_GOOGLE_TOKEN_CACHE" ]; then
    local cached_ts
    cached_ts=$(stat -c %Y "$_GOOGLE_TOKEN_CACHE" 2>/dev/null || echo 0)
    local now; now=$(date +%s)
    local age=$(( now - cached_ts ))
    if [ "$age" -lt 3000 ]; then  # 50 minutes
      cat "$_GOOGLE_TOKEN_CACHE"
      return 0
    fi
  fi

  # Refresh via gcloud
  if ! command -v gcloud >/dev/null 2>&1; then
    echo -e "  \033[1;31mgcloud CLI not found.\033[0m" >&2
    return 1
  fi

  local token
  token=$(gcloud auth print-access-token 2>/dev/null) || {
    echo -e "  \033[1;31mFailed to get gcloud access token.\033[0m" >&2
    echo -e "  \033[0;90m(Try: gcloud auth login)\033[0m" >&2
    return 1
  }

  printf '%s' "$token" > "$_GOOGLE_TOKEN_CACHE"
  printf '%s' "$token"
  return 0
}

# ─── Extra headers (none needed — OpenAI-compatible uses Bearer auth) ───────
google_extra_headers_json() {
  local mode
  mode=$(grep '^mode=' "$_GOOGLE_CONFIG_FILE" 2>/dev/null | cut -d= -f2-) || true

  if [ "$mode" = "vertex" ]; then
    # Vertex with API key: use x-goog-api-key header, suppress Authorization
    local key="${GOOGLE_API_KEY:-}"
    if [ -z "$key" ] && [ -f "$_GOOGLE_KEY_FILE" ]; then
      key=$(cat "$_GOOGLE_KEY_FILE")
    fi
    python3 -c "
import json
h = {
    'x-goog-api-key': '''$key''',
    'Authorization': None
}
print(json.dumps(h))
"
  else
    # Studio: standard Bearer auth (default pipeline handles it)
    echo "{}"
  fi
}

# ─── List models ────────────────────────────────────────────────────────────
google_list_models() {
  echo -e "  \033[1;37mGoogle Gemini Models\033[0m"
  echo ""
  for m in "${_GOOGLE_MODELS[@]}"; do
    local marker=" "
    [ "$m" = "$MODEL" ] && marker="*"
    echo -e "  $marker $m"
  done
  echo ""
  echo "  Set with: /model <name>"
  echo "  Docs: https://ai.google.dev/gemini-api/docs/models"
}

# ─── Validate model ─────────────────────────────────────────────────────────
google_validate_model() {
  local model_id="$1"
  for m in "${_GOOGLE_MODELS[@]}"; do
    if [ "$m" = "$model_id" ]; then
      return 0
    fi
  done

  # Not in known list — check for prefix match (e.g. gemini-2.5-pro-preview-xxx)
  case "$model_id" in
    gemini-*)
      # Allow unknown gemini models with a note
      echo "(Model '$model_id' not in known list but matches gemini prefix — proceeding)"
      return 0
      ;;
  esac

  # Suggest closest match
  local needle="${model_id,,}"
  local suggestions=()
  for m in "${_GOOGLE_MODELS[@]}"; do
    if [[ "${m,,}" == *"$needle"* ]] || [[ "$needle" == *"${m,,}"* ]]; then
      suggestions+=("$m")
    fi
  done

  if [ ${#suggestions[@]} -gt 0 ]; then
    echo "Did you mean: ${suggestions[*]}?"
  else
    echo "Unknown model '$model_id'. Available: ${_GOOGLE_MODELS[*]}"
  fi
  return 1
}
