# ─── Provider: GitHub Copilot ────────────────────────────────────────────────
# Reference provider implementation. Uses GitHub device-flow OAuth to get a
# short-lived Copilot API token, then hits api.githubcopilot.com which is
# fully OpenAI-compatible (same payload, same streaming format).
#
# Auth flow:
#   1. POST github.com/login/device/code  → device_code + user_code
#   2. User visits https://github.com/login/device, enters user_code
#   3. Poll POST github.com/login/oauth/access_token → github_token
#   4. GET  api.github.com/copilot_internal/v2/token → copilot_token (30min TTL)
#   5. Bearer copilot_token on api.githubcopilot.com/chat/completions
#
# Config:
#   PROVIDER=copilot
#   MODEL=gpt-4o  (or claude-sonnet-4-20250514, o3, etc.)
#
# Files:
#   ~/.mix/copilot_github_token  — persisted GitHub OAuth token (step 3)
#   /tmp/mix-copilot-token       — cached Copilot API token (step 4, auto-refreshes)

_COPILOT_CLIENT_ID="Iv1.b507a08c87ecfe98"  # GitHub Copilot CLI client ID (public)
_COPILOT_GH_TOKEN_FILE="${HOME}/.mix/copilot_github_token"

# ─── Step 1-3: GitHub device-flow OAuth ────────────────────────────────────
copilot_login() {
  echo "  \033[1;37mGitHub Copilot Login\033[0m"

  # Request device code
  local resp
  resp=$(curl -s -X POST "https://github.com/login/device/code" \
    -H "Accept: application/json" \
    -d "client_id=${_COPILOT_CLIENT_ID}&scope=user:email" 2>/dev/null) || {
    echo "  \033[1;31mFailed to reach GitHub. Check network.\033[0m"
    return 1
  }

  local device_code user_code verification_uri
  device_code=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["device_code"])' 2>/dev/null)
  user_code=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["user_code"])' 2>/dev/null)
  verification_uri=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["verification_uri"])' 2>/dev/null)

  if [ -z "$device_code" ] || [ -z "$user_code" ]; then
    echo "  \033[1;31mFailed to get device code from GitHub.\033[0m"
    echo "  Response: $resp"
    return 1
  fi

  echo ""
  echo "  \033[1;33m  Code: $user_code\033[0m"
  echo "  Open: \033[4m${verification_uri}\033[0m"
  echo "  (code copied — paste it in the browser)"
  echo ""

  # Try to copy code to clipboard
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$user_code" | wl-copy 2>/dev/null
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$user_code" | xclip -selection clipboard 2>/dev/null
  elif command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$user_code" | pbcopy 2>/dev/null
  fi

  # Poll for token (GitHub says interval=5s)
  local interval=5
  local gh_token=""
  echo "  Waiting for authorization..."
  while true; do
    sleep "$interval"
    local poll_resp
    poll_resp=$(curl -s -X POST "https://github.com/login/oauth/access_token" \
      -H "Accept: application/json" \
      -d "client_id=${_COPILOT_CLIENT_ID}&device_code=${device_code}&grant_type=urn:ietf:params:oauth:grant-type:device_code" 2>/dev/null) || true

    local error
    error=$(printf '%s' "$poll_resp" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("error",""))' 2>/dev/null)

    if [ "$error" = "authorization_pending" ]; then
      continue
    elif [ "$error" = "slow_down" ]; then
      interval=$((interval + 5))
      continue
    elif [ "$error" = "expired_token" ]; then
      echo "  \033[1;31mDevice code expired. Run /provider copilot login again.\033[0m"
      return 1
    elif [ -z "$error" ]; then
      gh_token=$(printf '%s' "$poll_resp" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
      if [ -n "$gh_token" ]; then
        break
      fi
    else
      echo "  \033[1;31mUnexpected error: $error\033[0m"
      return 1
    fi
  done

  # Persist GitHub token
  mkdir -p "$(dirname "$_COPILOT_GH_TOKEN_FILE")"
  chmod 700 "$(dirname "$_COPILOT_GH_TOKEN_FILE")"
  printf '%s' "$gh_token" > "$_COPILOT_GH_TOKEN_FILE"
  chmod 600 "$_COPILOT_GH_TOKEN_FILE"

  echo "  \033[38;5;82m✓ GitHub token saved.\033[0m"
  return 0
}

# ─── Step 4: Exchange GitHub token → Copilot API token ─────────────────────
copilot_get_api_token() {
  # Check for cached token (valid ~30min)
  local cache_file="/tmp/mix-copilot-api-token"
  if [ -f "$cache_file" ]; then
    local cached_ts cached_token
    cached_ts=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    local now; now=$(date +%s)
    local age=$(( now - cached_ts ))
    # Refresh if older than 25 minutes (token lasts 30min)
    if [ "$age" -lt 1500 ]; then
      cat "$cache_file"
      return 0
    fi
  fi

  local gh_token
  if [ -f "$_COPILOT_GH_TOKEN_FILE" ]; then
    gh_token=$(cat "$_COPILOT_GH_TOKEN_FILE")
  fi

  if [ -z "$gh_token" ]; then
    echo "  \033[1;33mNo GitHub token. Run: /provider copilot login\033[0m" >&2
    return 1
  fi

  local resp
  resp=$(curl -s "https://api.github.com/copilot_internal/v2/token" \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/json" 2>/dev/null) || {
    echo "  \033[1;31mFailed to get Copilot token.\033[0m" >&2
    return 1
  }

  local api_token
  api_token=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("token",""))' 2>/dev/null)

  if [ -z "$api_token" ]; then
    local err
    err=$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("message","unknown"))' 2>/dev/null)
    echo "  \033[1;31mCopilot token error: $err\033[0m" >&2
    echo "  \033[0;90m(Try: /provider copilot login)\033[0m" >&2
    return 1
  fi

  # Cache it
  printf '%s' "$api_token" > "$cache_file"
  printf '%s' "$api_token"
  return 0
}

# ─── Provider hooks (called by mix core) ───────────────────────────────────

# Return the API key to use. For Copilot, we auto-refresh the short-lived token.
copilot_get_api_key() {
  copilot_get_api_token
}

# Return extra headers for curl (newline-separated)
copilot_curl_headers() {
  echo "-H \"Editor-Version: Neovim/0.9.5\""
  echo "-H \"Editor-Plugin-Version: copilot.vim/1.16.0\""
  echo "-H \"Openai-Organization: github-copilot\""
  echo "-H \"Openai-Intent: copilot-panel\""
}

# Return extra env vars for python3 streaming (space-separated KEY=VALUE pairs)
copilot_stream_env() {
  echo "COPILOT_HEADERS=1"
}

# Copilot streaming python3 needs these extra headers injected
# This function is called from within call_api_stream's python3 block
copilot_extra_headers_json() {
  python3 -c '
import json
h = {
    "Editor-Version": "Neovim/0.9.5",
    "Editor-Plugin-Version": "copilot.vim/1.16.0",
    "Openai-Organization": "github-copilot",
    "Openai-Intent": "copilot-panel"
}
print(json.dumps(h))
'
}

# ─── List available models ─────────────────────────────────────────────────
copilot_list_models() {
  local api_token
  api_token=$(copilot_get_api_token) || return 1

  curl -s "https://api.githubcopilot.com/models" \
    -H "Authorization: Bearer $api_token" \
    -H "Accept: application/json" \
    -H "Editor-Version: Neovim/0.9.5" \
    -H "Editor-Plugin-Version: copilot.vim/1.16.0" \
    -H "Openai-Organization: github-copilot" 2>/dev/null | python3 -c '
import json,sys
try:
  data = json.load(sys.stdin)
  models = data.get("data", [])
  for m in models:
    mid = m.get("id","?")
    name = m.get("name", mid)
    caps = m.get("capabilities",{})
    streaming = "stream" if caps.get("streaming",False) else "no-stream"
    tools = "tools" if caps.get("tool_calls",False) else "no-tools"
    print(f"  {mid:<40} {name:<30} [{streaming}] [{tools}]")
except Exception as e:
  print(f"  Error parsing models: {e}")
' 2>/dev/null
}

# ─── Set provider to copilot ───────────────────────────────────────────────
copilot_activate() {
  # Check for GitHub token first
  if [ ! -f "$_COPILOT_GH_TOKEN_FILE" ]; then
    echo "  \033[1;33mNot logged in. Run: /provider copilot login\033[0m"
    return 1
  fi

  # Get API token to verify auth works
  local api_token
  api_token=$(copilot_get_api_token) || {
    echo "  \033[1;31mAuth failed. Try: /provider copilot login\033[0m"
    return 1
  }

  # Override config
  BASE_URL="https://api.githubcopilot.com"
  PROVIDER="copilot"
  MODEL="${AGENT_MODEL:-gpt-4o}"

  echo "  \033[38;5;82m✓ Provider → copilot\033[0m"
  echo "  Base URL: $BASE_URL"
  echo "  Model: $MODEL"
  echo "  Run \033[1m/provider copilot models\033[0m to list available models"
  echo "  Run \033[1m/model <id>\033[0m to switch models"
}
