# ─── Lightweight planning call (plan mode) ───────────────────────────────────
call_api_plan() {
  local payload
  payload=$(printf '%s\n%s\n%s\n' \
    "$(build_system_prompt | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$HISTORY" \
    "$MODEL" \
  | python3 -c '
import json,sys
s=json.loads(sys.stdin.readline())
h=json.loads(sys.stdin.readline())
m=sys.stdin.readline().strip()
msg=[{"role":"system","content":s}]+h
msg.append({"role":"user","content":"List your plan as a numbered list (3-7 steps) before acting. Be concise."})
print(json.dumps({"model":m,"messages":msg}))
' 2>/dev/null) || return 1
  local tmp; tmp=$(mktemp)
  local code
  code=$(curl -s -w "%{http_code}" -o "$tmp" --max-time 30 \
    "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" = "200" ] && printf '%s' "$body" | python3 -c \
    'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"].get("content",""))' 2>/dev/null || true
}

