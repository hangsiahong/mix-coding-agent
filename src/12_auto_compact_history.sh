# ─── Auto-compact history ────────────────────────────────────────────────────
# When history exceeds MAX_HIST_MSGS, ask the model to summarize old messages,
# then replace them with a single context message + keep last 10 turns verbatim.
compact_history() {
  # Fast path: use cheap counter instead of spawning python3 to count
  local count
  count=$(printf '%s' "$HISTORY" | grep -o '"role"' | wc -l) || return
  
  local _hist_chars=${#HISTORY}
  local _est_tokens=$(( _hist_chars / 3 ))
  local _should_compact=false
  
  if [ "$count" -ge "$MAX_HIST_MSGS" ]; then
    _should_compact=true
  elif [ "$_est_tokens" -ge "$(( CTX_TOKENS * 85 / 100 ))" ]; then
    _should_compact=true
  fi
  
  [ "$_should_compact" = false ] && return

  # Resolve API key — provider may override
  local _compact_key="$API_KEY"
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_get_api_key" >/dev/null 2>&1; then
    local _pkey; _pkey=$(${PROVIDER}_get_api_key 2>/dev/null) || true
    [ -n "$_pkey" ] && _compact_key="$_pkey"
  fi

  # Build payload via temp files
  # Apply model prefix (e.g. Google Vertex needs "google/" prefix)
  local _compact_model="$MODEL"
  [ -n "${_GOOGLE_VERTEX_MODEL_PREFIX:-}" ] && _compact_model="${_GOOGLE_VERTEX_MODEL_PREFIX}${MODEL}"

  local _payload_tmp; _payload_tmp=$(mktemp -t mix-$$-compact-XXXXXX)
  local _hist_tmp; _hist_tmp=$(mktemp -t mix-$$-hist-XXXXXX)
  # Sanitize history for current provider (strips thought_sig cross-provider)
  local _hist_for_compact
  _hist_for_compact=$(_apply_provider_history_filter "$HISTORY") || _hist_for_compact="$HISTORY"
  printf '%s' "$_hist_for_compact" > "$_hist_tmp"
  python3 -c '
import json,sys
s="Summarize the conversation into a dense structured summary. Use these sections:\n## Task\nWhat is the user trying to accomplish? What is the current goal?\n## Done\nKey decisions made, files edited/created, commands run, bugs fixed.\n## State\nWhere things stand right now. Any open loops, pending actions, or blockers.\n## Context\nImportant paths, variable names, API details, or config values referenced.\n\nRules:\n- Do NOT include full file contents — they are available in the file cache.\n- Do NOT repeat tool outputs verbatim — extract conclusions only.\n- Do NOT include diagnostic/verify output — only the final resolution.\n- Include: file paths edited, key variable names, error patterns resolved.\n- Be complete but concise. Output only the summary, nothing else."
h=json.load(open(sys.argv[1]))
m=sys.argv[2]
msg=h+[{"role":"user","content":s}]
json.dump({"model":m,"messages":msg},open(sys.argv[3],"w"))
' "$_hist_tmp" "$_compact_model" "$_payload_tmp" 2>/dev/null || {
    rm -f "$_payload_tmp" "$_hist_tmp"
    printf "\r\033[K  \033[0;33m$I_RETRY compact failed: payload build error\033[0m\n"
    return
  }
  rm -f "$_hist_tmp"

  # Build curl args — same SUPPRESS_AUTH logic as call_api
  local _curl_args=(-s -w "%{http_code}" --max-time 90
    "${BASE_URL}/chat/completions"
    -H "Content-Type: application/json")

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

  [ "$_suppress_auth" = "false" ] && [ -n "$_compact_key" ] && \
    _curl_args+=(-H "Authorization: Bearer $_compact_key")

  if [ -n "$_extra_pairs" ]; then
    while IFS=$'\t' read -r _hk _hv; do
      [ "$_hk" = "SUPPRESS_AUTH" ] && continue
      [ -n "$_hk" ] && [ -n "$_hv" ] && _curl_args+=(-H "$_hk: $_hv")
    done <<< "$_extra_pairs"
  fi

  # Start spinner animation
  local _spinner_pid
  _spinner_anim() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    tput sc
    while true; do
      printf "\r\033[K  \033[0;36m%s\033[0m \033[0;90mcompacting history (%d msgs)...\033[0m" "${frames[$((i % ${#frames[@]}))]}" "$1"
      i=$((i + 1))
      sleep 0.08
    done
  }
  _spinner_anim "$count" &
  _spinner_pid=$!

  local _resp_tmp; _resp_tmp=$(mktemp -t mix-$$-compact-resp-XXXXXX)
  local code
  code=$(curl "${_curl_args[@]}" -o "$_resp_tmp" -d "@$_payload_tmp" 2>/dev/null) || true
  rm -f "$_payload_tmp"

  # Stop spinner
  kill "$_spinner_pid" 2>/dev/null
  wait "$_spinner_pid" 2>/dev/null

  if [ "$code" != "200" ]; then
    local _err; _err=$(cat "$_resp_tmp" 2>/dev/null | head -c 200)
    rm -f "$_resp_tmp"
    printf "\r\033[K  \033[0;33m$I_RETRY compact failed: API %s\033[0m\n" "${code:-timeout}"
    return
  fi

  local summary
  local _py_err
  _py_err=$(mktemp -t mix-$$-compact-err-XXXXXX)
  summary=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1],"rb")); print(d["choices"][0]["message"]["content"])' "$_resp_tmp" 2>"$_py_err")
  local _py_rc=$?
  if [ -z "$summary" ] || [ $_py_rc -ne 0 ]; then
    local _raw_preview; _raw_preview=$(head -c 500 "$_resp_tmp" 2>/dev/null)
    local _py_msg; _py_msg=$(cat "$_py_err" 2>/dev/null)
    rm -f "$_resp_tmp" "$_py_err"
    printf "\r\033[K  \033[0;33m$I_RETRY compact failed: empty summary (py rc=%d)\033[0m\n" "$_py_rc"
    [ -n "$_py_msg" ] && printf "  \033[0;90mpython error: %s\033[0m\n" "$(printf '%s' "$_py_msg" | head -c 300)"
    printf "  \033[0;90mAPI response (first 500 chars): %s\033[0m\n" "$_raw_preview"
    return
  fi
  rm -f "$_resp_tmp" "$_py_err"

  # Keep last 10 messages verbatim
  local recent
  recent=$(printf '%s' "$HISTORY" | python3 -c \
    'import json,sys;h=json.load(sys.stdin);print(json.dumps(h[-10:]))' 2>/dev/null) || recent='[]'

  # New history: summary injection + recent tail
  local sum_esc
  sum_esc=$(printf '[Compacted context]\n%s' "$summary" \
    | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null) || {
      printf "\r\033[K  \033[0;33m$I_RETRY compact failed: escape error\033[0m\n"
      return
    }

  local _compacted
  _compacted=$(printf '%s\n%s' \
    "[{\"role\":\"user\",\"content\":$sum_esc},{\"role\":\"assistant\",\"content\":\"Context loaded. Reviewing summary. Ready to continue — pick up where we left off.\"}]" \
    "$recent" \
  | python3 -c '
import json,sys
lines=sys.stdin.read().strip().splitlines()
if not lines: sys.exit(1)
base=json.loads(lines[0])
recent=json.loads(lines[1])
print(json.dumps(base+recent))
' 2>/dev/null) || {
      printf "\r\033[K  \033[0;33m$I_RETRY compact failed: merge error\033[0m\n"
      return
    }

  # Only update HISTORY if we actually got a valid result
  if [ -n "$_compacted" ]; then
    HISTORY="$_compacted"
    save_history
    _sysprompt_invalidate  # context budget changed
    local new_count
    new_count=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || new_count="?"
    printf "\r\033[K  \033[38;5;82m$I_OK compacted: %d → %s msgs\033[0m\n" "$count" "$new_count"
  else
    printf "\r\033[K  \033[0;33m$I_RETRY compact failed: no result\033[0m\n"
  fi
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

# Like append_raw but skips the disk write — call save_history manually after a batch
append_raw_nosave() {
  local msg="$1"
  if [ "$HISTORY" = "[]" ]; then
    HISTORY="[$msg]"
  else
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
}

append_text() {
  local role="$1" content="$2"
  local escaped
  
  # Image preview support: if content contains [image: /path/to/img], parse it into a multimodal array
  # Note: Currently assumes only text or 1 image + text. The model expects OpenAI vision format.
  escaped=$(printf '%s' "$content" | python3 -c '
import json,sys,re,base64,os
text = sys.stdin.read()
matches = re.findall(r"\[image:\s*(.*?)\s*\]", text)
if not matches:
    print(json.dumps(text))
else:
    # Convert text to array of content parts
    parts = []
    # Strip the image tag from text to avoid duplication if we want
    clean_text = re.sub(r"\[image:\s*(.*?)\s*\]", "", text).strip()
    if clean_text:
        parts.append({"type":"text", "text":clean_text})
    
    for img_path in matches:
        if os.path.exists(img_path):
            try:
                with open(img_path, "rb") as f:
                    b64 = base64.b64encode(f.read()).decode("utf-8")
                # Detect mime
                mime = "image/png"
                if img_path.lower().endswith(".jpg") or img_path.lower().endswith(".jpeg"): mime = "image/jpeg"
                parts.append({"type":"image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})
            except:
                pass
    if not parts:
        print(json.dumps(text))
    else:
        print(json.dumps(parts))
')
  append_raw "{\"role\":\"$role\",\"content\":$escaped}"
}

