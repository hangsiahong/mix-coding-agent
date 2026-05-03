# ─── Auto-compact history ────────────────────────────────────────────────────
# When history exceeds MAX_HIST_MSGS, ask the model to summarize old messages,
# then replace them with a single context message + keep last 10 turns verbatim.
compact_history() {
  local count
  count=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || return
  [ "$count" -lt "$MAX_HIST_MSGS" ] && return

  printf "\r\033[K  \033[0;90m↻ compacting history (%d msgs)...\033[0m" "$count"

  # Build a summarise-only payload (no tools, no system tools overhead)
  local payload
  payload=$(printf '%s\n%s\n%s\n' \
    "$(printf 'Summarize the conversation below into a single dense paragraph. Capture: goals, decisions made, files edited, commands run, errors resolved, current state. Be complete but concise. Output only the summary paragraph, nothing else.' \
        | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    "$HISTORY" \
    "$MODEL" \
  | python3 -c '
import json,sys
s=json.loads(sys.stdin.readline())
h=json.loads(sys.stdin.readline())
m=sys.stdin.readline().strip()
msg=[{"role":"system","content":s}]+h
print(json.dumps({"model":m,"messages":msg}))
' 2>/dev/null) || { echo ""; return; }

  # Resolve API key — provider may override
  local _compact_key="$API_KEY"
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_get_api_key" >/dev/null 2>&1; then
    local _pkey; _pkey=$(${PROVIDER}_get_api_key 2>/dev/null) || true
    [ -n "$_pkey" ] && _compact_key="$_pkey"
  fi
  # Build curl args with provider extra headers (e.g. Copilot Editor-Version)
  local _curl_args=(-s -w "%{http_code}" --max-time 60
    "${BASE_URL}/chat/completions"
    -H "Authorization: Bearer $_compact_key"
    -H "Content-Type: application/json")
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_extra_headers_json" >/dev/null 2>&1; then
    local _ph; _ph=$(${PROVIDER}_extra_headers_json 2>/dev/null) || true
    if [ -n "$_ph" ]; then
      while IFS= read -r _hk _hv; do
        [ -n "$_hk" ] && _curl_args+=(-H "$_hk: $_hv")
      done < <(printf '%s' "$_ph" | python3 -c '
import json,sys
for k,v in json.load(sys.stdin).items(): print(f"{k} {v}")
' 2>/dev/null)
    fi
  fi

  local tmp; tmp=$(mktemp -t mix-XXXXXX)
  local code
  code=$(curl "${_curl_args[@]}" -o "$tmp" -d "$payload" 2>/dev/null) || true
  local body; body=$(cat "$tmp"); rm -f "$tmp"

  if [ "$code" != "200" ]; then echo ""; return; fi

  local summary
  summary=$(printf '%s' "$body" | python3 -c \
    'import json,sys;print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null) || { echo ""; return; }

  # Keep last 10 messages verbatim
  local recent
  recent=$(printf '%s' "$HISTORY" | python3 -c \
    'import json,sys;h=json.load(sys.stdin);print(json.dumps(h[-10:]))' 2>/dev/null) || recent='[]'

  # New history: summary injection + recent tail
  local sum_esc
  sum_esc=$(printf '[Compacted context]\n%s' "$summary" \
    | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null) || { echo ""; return; }

  local _compacted
  _compacted=$(printf '%s\n%s' \
    "[{\"role\":\"user\",\"content\":$sum_esc},{\"role\":\"assistant\",\"content\":\"Understood. Context loaded.\"}]" \
    "$recent" \
  | python3 -c '
import json,sys
lines=sys.stdin.read().strip().splitlines()
base=json.loads(lines[0])
recent=json.loads(lines[1])
print(json.dumps(base+recent))
' 2>/dev/null) || { echo ""; return; }
  # Only update HISTORY if we actually got a valid result
  [ -n "$_compacted" ] && HISTORY="$_compacted"

  save_history
  local new_count
  new_count=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || new_count="?"
  printf "\r\033[K  \033[0;90m↻ compacted: %d → %s msgs\033[0m\n" "$count" "$new_count"
}

append_raw() {
  local msg="$1"
  if [ "$HISTORY" = "[]" ]; then
    HISTORY="[$msg]"
  else
    # Pass msg via stdin (2nd line) to avoid ARG_MAX limits on large histories
    local _new
    _new=$(printf '%s\n%s' "$HISTORY" "$msg" | python3 -c '
import json,sys
lines=sys.stdin.read().split("\n",1)
h=json.loads(lines[0])
h.append(json.loads(lines[1]))
print(json.dumps(h))
' 2>/dev/null)
    [ -n "$_new" ] && HISTORY="$_new"
  fi
  save_history
}

append_text() {
  local role="$1" content="$2"
  local escaped
  escaped=$(printf '%s' "$content" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')
  append_raw "{\"role\":\"$role\",\"content\":$escaped}"
}

