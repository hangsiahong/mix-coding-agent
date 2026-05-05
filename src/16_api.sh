# ─── API ─────────────────────────────────────────────────────────────────────
call_api() {
  local payload
  local _model="$MODEL"
  [ -n "${_GOOGLE_VERTEX_MODEL_PREFIX:-}" ] && _model="${_GOOGLE_VERTEX_MODEL_PREFIX}${MODEL}"
  # Sanitize history for current provider (handles provider switching seamlessly)
  local _hist_for_api
  _hist_for_api=$(_apply_provider_history_filter "$HISTORY") || _hist_for_api="$HISTORY"
  payload=$(printf '%s\n%s\n%s\n%s\n' \
    "$(build_system_prompt | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$TOOLS_JSON" \
    "$_hist_for_api" \
    "$_model" \
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

  # Build curl headers — merge default + provider extras (null = suppress)
  local _suppress_auth=false
  local _extra_pairs=""
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_extra_headers_json" >/dev/null 2>&1; then
    local _pheaders; _pheaders=$(${PROVIDER}_extra_headers_json 2>/dev/null) || true
    if [ -n "$_pheaders" ]; then
      _extra_pairs=$(printf '%s' "$_pheaders" | python3 -c '
import json,sys
for k,v in json.load(sys.stdin).items():
    if v is None:
        if k.lower()=="authorization": print("SUPPRESS_AUTH")
    else:
        print(f"{k}\t{v}")
' 2>/dev/null) || true
      echo "$_extra_pairs" | grep -q '^SUPPRESS_AUTH' && _suppress_auth=true
    fi
  fi

  local _curl_args=(-s -w "%{http_code}" --max-time 1800
    "${BASE_URL}/chat/completions"
    -H "Content-Type: application/json")
  [ "$_suppress_auth" = "false" ] && _curl_args+=(-H "Authorization: Bearer $_api_key")

  # Add provider extra headers (skip SUPPRESS_AUTH marker)
  if [ -n "$_extra_pairs" ]; then
    while IFS=$'\t' read -r _hk _hv; do
      [ "$_hk" = "SUPPRESS_AUTH" ] && continue
      [ -n "$_hk" ] && [ -n "$_hv" ] && _curl_args+=(-H "$_hk: $_hv")
    done <<< "$_extra_pairs"
  fi

  local tmp; tmp=$(mktemp -t mix-XXXXXX)
  local code
  code=$(curl "${_curl_args[@]}" -o "$tmp" -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" != "200" ] && { echo "FAIL:$code:$body"; return 1; }
  printf '%s' "$body"
}

