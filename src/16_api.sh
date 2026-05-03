# ─── API ─────────────────────────────────────────────────────────────────────
call_api() {
  local payload
  payload=$(printf '%s\n%s\n%s\n%s\n' \
    "$(build_system_prompt | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$TOOLS_JSON" \
    "$HISTORY" \
    "$MODEL" \
  | python3 -c '
import json,sys
s=json.loads(sys.stdin.readline())
t=json.loads(sys.stdin.readline())
h=json.loads(sys.stdin.readline())
m=sys.stdin.readline().strip()
msg=[{"role":"system","content":s}]+h
print(json.dumps({"model":m,"messages":msg,"tools":t,"tool_choice":"auto"}))
' 2>/dev/null) || { echo "FAIL:payload"; return 1; }

  # Resolve API key — provider may override
  local _api_key="$API_KEY"
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_get_api_key" >/dev/null 2>&1; then
    local _pkey; _pkey=$(${PROVIDER}_get_api_key 2>/dev/null) || true
    [ -n "$_pkey" ] && _api_key="$_pkey"
  fi

  # Build extra curl headers from provider
  local _extra_headers=""
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_curl_headers" >/dev/null 2>&1; then
    _extra_headers=$(${PROVIDER}_curl_headers 2>/dev/null) || true
  fi

  local tmp; tmp=$(mktemp -t mix-XXXXXX)
  local code
  eval curl -s -w '"%{http_code}"' -o '"$tmp"' --max-time 1800 \
    '"${BASE_URL}/chat/completions"' \
    -H '"Authorization: Bearer $_api_key"' \
    -H '"Content-Type: application/json"' \
    $_extra_headers \
    -d '"$payload"' 2>/dev/null || true
  code=$(cat "$tmp.code" 2>/dev/null)
  # Re-run with proper status capture
  code=$(curl -s -w "%{http_code}" -o "$tmp" --max-time 1800 \
    "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer $_api_key" \
    -H "Content-Type: application/json" \
    $(echo $_extra_headers) \
    -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" != "200" ] && { echo "FAIL:$code:$body"; return 1; }
  printf '%s' "$body"
}

