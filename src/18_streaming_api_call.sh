# ─── Streaming API call ───────────────────────────────────────────────────────
# Streams content tokens live to /dev/tty. Returns same RAW/TC/TEXT format.
call_api_stream() {
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
print(json.dumps({"model":m,"messages":msg,"tools":t,"tool_choice":"auto","stream":True,"stream_options":{"include_usage":True}}))
' 2>/dev/null) || { echo "FAIL:payload"; return 1; }

  # Resolve API key — provider may override
  local _api_key="$API_KEY"
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_get_api_key" >/dev/null 2>&1; then
    local _pkey; _pkey=$(${PROVIDER}_get_api_key 2>/dev/null) || true
    [ -n "$_pkey" ] && _api_key="$_pkey"
  fi

  # Resolve extra headers from provider (JSON string)
  local _extra_headers="{}"
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_extra_headers_json" >/dev/null 2>&1; then
    local _ph; _ph=$(${PROVIDER}_extra_headers_json 2>/dev/null) || true
    [ -n "$_ph" ] && _extra_headers="$_ph"
  fi

  local tmp_out; tmp_out=$(mktemp -t mix-XXXXXX)
  
  BASE_URL="$BASE_URL" API_KEY="$_api_key" EXTRA_HEADERS="$_extra_headers" IS_INTERACTIVE="$INTERACTIVE" python3 -u -c '
import json,sys,base64,os,re,urllib.request,urllib.error
tty=open("/dev/tty","w") if os.path.exists("/dev/tty") and os.environ.get("IS_INTERACTIVE") != "false" else sys.stderr

url = os.environ.get("BASE_URL") + "/chat/completions"
api_key = os.environ.get("API_KEY")
payload = sys.stdin.read().encode("utf-8")

# Build headers: base + provider extras
hdrs = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json"
}
try:
    extra = json.loads(os.environ.get("EXTRA_HEADERS","{}"))
    hdrs.update(extra)
    hdrs = {k:v for k,v in hdrs.items() if v is not None}
except: pass

req = urllib.request.Request(url, data=payload, headers=hdrs)

content=[]
tcs={}
first=True
is_done=False
was_interrupted=False
usage={}

def kill_spinner():
    spin_pid = os.environ.get("SPIN_PID")
    if spin_pid:
        try: os.kill(int(spin_pid), 15)
        except: pass

try:
    with urllib.request.urlopen(req, timeout=1800) as response:
        for line in response:
            line = line.decode("utf-8").rstrip("\n\r")
            if not line: continue
            if not line.startswith("data: "):
                if "error" in line.lower() and "{" in line:
                    kill_spinner()
                    tty.write("\r\033[K    \033[38;5;196mAPI Error: " + line + "\033[0m\n")
                continue
            
            d=line[6:]
            if d=="[DONE]": 
                is_done=True
                break
            try: obj=json.loads(d)
            except: continue
            if obj.get("usage"): usage=obj["usage"]
            ch=obj.get("choices",[{}])[0]
            delta=ch.get("delta",{})
            tok=delta.get("content") or ""
            if tok:
                if first:
                    kill_spinner()
                    # Only print the header if we are NOT in the middle of a turn loop
                    # Actually, the agent loop handles the header for non-streaming.
                    # For streaming, we print it here.
                    tty.write("\r\033[K  \033[38;5;99m◆\033[0m \033[1mmix\033[0m\n    ")
                    tty.flush(); first=False
                tok = tok.replace("\n", "\n    ")
                tty.write(tok); tty.flush()
                content.append(tok)
            for tc in delta.get("tool_calls",[]):
                if first:
                    kill_spinner()
                    tty.write("\r\033[K")
                    tty.flush(); first=False
                i=tc.get("index",0)
                if i not in tcs: tcs[i]={"id":"","name":"","args":"","sig":""}
                if tc.get("id"): tcs[i]["id"]+=tc["id"]
                if tc.get("thought_signature"): tcs[i]["sig"]+=tc["thought_signature"]
                f=tc.get("function",{})
                if f.get("name"): tcs[i]["name"]+=f["name"]
                if f.get("arguments"): tcs[i]["args"]+=f["arguments"]
except KeyboardInterrupt:
    was_interrupted=True
    kill_spinner()
    tty.write("\n    \033[38;5;196m[Cancelled by User]\033[0m\n")
    tty.flush()
except urllib.error.HTTPError as e:
    kill_spinner()
    try: body = e.read().decode("utf-8","replace")
    except: body = ""
    tty.write(f"\n    \033[38;5;196m[API Request Failed: {str(e)}]\033[0m\n")
    if body: tty.write(f"    \033[38;5;196m{body}\033[0m\n")
    tty.flush()
except Exception as e:
    kill_spinner()
    tty.write(f"\n    \033[38;5;196m[API Request Failed: {str(e)}]\033[0m\n")
    tty.flush()

if was_interrupted:
    sys.stdout.write("FAIL:interrupted\n")
    sys.stdout.flush()
    sys.exit(0)

if not is_done and not was_interrupted:
    kill_spinner()
    tty.write("\n    \033[38;5;196m[Connection dropped prematurely by the API server]\033[0m")
    tty.flush()
    sys.stdout.write("FAIL:network_drop\n")
    sys.stdout.flush()
    sys.exit(0)

full="".join(content).replace("\n    ", "\n")
if full:
    tty.write("\n")
    tty.flush()
    # ── Post-stream markdown render: erase streamed output, reprint rendered ──
    rendered_lines = []
    in_code_block = False
    code_lang = ""
    for raw_line in full.split("\n"):
        # Fenced code blocks
        if raw_line.startswith("```"):
            if not in_code_block:
                in_code_block = True
                code_lang = raw_line[3:].strip()
                rendered_lines.append("\033[0;90m  ┌─" + (f" {code_lang} " if code_lang else "") + "\033[0m")
            else:
                in_code_block = False
                rendered_lines.append("\033[0;90m  └─\033[0m")
            continue
        if in_code_block:
            rendered_lines.append("\033[0;90m  │\033[0m \033[38;5;222m" + raw_line + "\033[0m")
            continue
        # Headers
        if raw_line.startswith("### "):
            rendered_lines.append("\033[1;36m" + raw_line[4:] + "\033[0m")
            continue
        if raw_line.startswith("## "):
            rendered_lines.append("\033[1;33m" + raw_line[3:] + "\033[0m")
            continue
        if raw_line.startswith("# "):
            rendered_lines.append("\033[1;37m" + raw_line[2:] + "\033[0m")
            continue
        # Bullet points
        line = raw_line
        if re.match(r"^[-*] ", line):
            line = "\033[38;5;99m•\033[0m " + line[2:]
        elif re.match(r"^\d+\. ", line):
            m = re.match(r"^(\d+\.) (.*)", line)
            if m: line = "\033[38;5;99m" + m.group(1) + "\033[0m " + m.group(2)
        # Inline: **bold**, `code`, *italic*
        line = re.sub(r"\*\*(.+?)\*\*", "\033[1m\\1\033[0m", line)
        line = re.sub(r"`([^`]+)`", "\033[38;5;222m\\1\033[0m", line)
        line = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", "\033[3m\\1\033[0m", line)
        rendered_lines.append(line)
    # Count lines streamed so we can erase them
    raw_display = "".join(content)
    # Use a safe over-count: count newlines in streamed content + header + indent lines
    # Each streamed line has "    " prefix but wraps differently than rendered.
    # Strategy: move up generously, clear to bottom, reprint. Over-erase is safe.
    streamed_line_count = raw_display.count("\n") + 2  # +2 for header line + last line
    # For short responses (<8 lines), skip re-render entirely — raw stream is readable
    if streamed_line_count <= 8:
        # Just ensure we end on a clean newline
        tty.write("\n")
        tty.flush()
    else:
        # Move up with extra margin to handle wrapping safely
        safe_count = streamed_line_count + 4
        tty.write(f"\033[{safe_count}A\033[J")
        tty.write("  \033[38;5;99m◆\033[0m \033[1mmix\033[0m\n")
        for rl in rendered_lines:
            tty.write("    " + rl + "\n")
        tty.flush()
msg={"role":"assistant","content":full}
if tcs:
    def make_tc(t):
        d={"id":t["id"],"type":"function","function":{"name":t["name"],"arguments":t["args"]}}
        if t.get("sig"): d["thought_signature"]=t["sig"]
        return d
    msg["tool_calls"]=[make_tc(tcs[i]) for i in sorted(tcs)]
if not full: msg["content"]=""
sys.stdout.write("RAW:"+base64.b64encode(json.dumps(msg).encode()).decode()+"\n")
if tcs:
    for i in sorted(tcs): sys.stdout.write("TC:"+tcs[i]["id"]+"|||"+tcs[i]["name"]+"|||"+tcs[i]["args"]+"\n")
if full:
    sys.stdout.write("TEXT:"+full+"\n")
elif not tcs:
    sys.stdout.write("TEXT:(empty)\n")
if usage:
    sys.stdout.write("USAGE:"+str(usage.get("prompt_tokens",0))+":"+str(usage.get("completion_tokens",0))+"\n")
sys.stdout.flush()
' <<< "$payload" > "$tmp_out"

  local result; result=$(cat "$tmp_out"); rm -f "$tmp_out"
  [ -z "$result" ] && { echo "FAIL:stream"; return 1; }
  printf '%s' "$result"
}

