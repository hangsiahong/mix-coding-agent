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

  # Build curl headers
  local _curl_args=(-s -w "%{http_code}" --max-time 1800
    "${BASE_URL}/chat/completions"
    -H "Authorization: Bearer $_api_key"
    -H "Content-Type: application/json")

  # Provider extra headers
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_extra_headers_json" >/dev/null 2>&1; then
    local _pheaders; _pheaders=$(${PROVIDER}_extra_headers_json 2>/dev/null) || true
    if [ -n "$_pheaders" ]; then
      while IFS= read -r _hk _hv; do
        [ -n "$_hk" ] && _curl_args+=(-H "$_hk: $_hv")
      done < <(printf '%s' "$_pheaders" | python3 -c '
import json,sys
for k,v in json.load(sys.stdin).items(): print(f"{k} {v}")
' 2>/dev/null)
    fi
  fi

  local tmp; tmp=$(mktemp -t mix-XXXXXX)
  local code
  code=$(curl "${_curl_args[@]}" -o "$tmp" -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" != "200" ] && { echo "FAIL:$code:$body"; return 1; }
  printf '%s' "$body"
}

