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

  local tmp; tmp=$(mktemp -t mix-XXXXXX)
  local code
  code=$(curl -s -w "%{http_code}" -o "$tmp" --max-time 1800 \
    "${BASE_URL}/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"
  [ "$code" != "200" ] && { echo "FAIL:$code:$body"; return 1; }
  printf '%s' "$body"
}

