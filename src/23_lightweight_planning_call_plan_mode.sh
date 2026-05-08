# ─── Lightweight planning call (plan mode) ───────────────────────────────────
call_api_plan() {
  local _plan_model="${PLAN_MODEL:-$MODEL}"
  local _plan_provider="${PLAN_PROVIDER:-$PROVIDER}"
  local _plan_base_url="$BASE_URL"
  local _plan_key="$API_KEY"

  if [ "$_plan_provider" != "$PROVIDER" ]; then
    # Cross-provider planning (e.g. use cheap Gemini while using Claude for main)
    # We need to look up config for the other provider
    # This is a bit complex in bash without a central registry, but we can check ENV
    local _p_upper; _p_upper=$(echo "$_plan_provider" | tr '[:lower:]' '[:upper:]')
    local _env_key; eval "_env_key=\${${_p_upper}_API_KEY:-}"
    [ -n "$_env_key" ] && _plan_key="$_env_key"
    local _env_url; eval "_env_url=\${${_p_upper}_BASE_URL:-}"
    [ -n "$_env_url" ] && _plan_base_url="$_env_url"
  fi

  local payload
  payload=$(printf '%s\n%s\n%s\n' \
    "$(build_system_prompt | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$HISTORY" \
    "$_plan_model" \
  | python3 -c '
import json,sys
s=json.loads(sys.stdin.readline())
h=json.loads(sys.stdin.readline())
m=sys.stdin.readline().strip()
msg=[{"role":"system","content":s}]+h
msg.append({"role":"user","content":"List your plan as a numbered list (3-7 steps) before acting. Be concise."})
print(json.dumps({"model":m,"messages":msg}))
' 2>/dev/null) || return 1
  local tmp; tmp=$(mktemp -t mix-$$-XXXXXX)
  local code
  code=$(curl -s -w "%{http_code}" -o "$tmp" --max-time 30 \
    "$_plan_base_url/chat/completions" \
    -H "Authorization: Bearer $_plan_key" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" = "200" ] && printf '%s' "$body" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"].get("content",""))' 2>/dev/null || true
}

