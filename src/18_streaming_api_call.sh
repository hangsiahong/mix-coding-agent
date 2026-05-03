# ─── Streaming API call ───────────────────────────────────────────────────────
# Streams content tokens live to /dev/tty. Returns same RAW/TC/TEXT format.
call_api_stream() {
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
print(json.dumps({"model":m,"messages":msg,"tools":t,"tool_choice":"auto","stream":True}))
' 2>/dev/null) || { echo "FAIL:payload"; return 1; }

  local tmp_out; tmp_out=$(mktemp -t mix-XXXXXX)
  
  # Replacing curl with pure Python urllib.request for better connection handling
  # and resolving partial file/premature drop errors natively.
  BASE_URL="$BASE_URL" API_KEY="$API_KEY" IS_INTERACTIVE="$INTERACTIVE" python3 -u -c '
import json,sys,base64,os,urllib.request,urllib.error
# If interactive=false, write to stderr so that pipes like `mix | tee` can log the streaming output
tty=open("/dev/tty","w") if os.path.exists("/dev/tty") and os.environ.get("IS_INTERACTIVE") != "false" else sys.stderr

url = os.environ.get("BASE_URL") + "/chat/completions"
api_key = os.environ.get("API_KEY")
payload = sys.stdin.read().encode("utf-8")

req = urllib.request.Request(
    url, 
    data=payload, 
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }
)

content=[]
tcs={}
first=True
is_done=False
was_interrupted=False

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
            ch=obj.get("choices",[{}])[0]
            delta=ch.get("delta",{})
            tok=delta.get("content") or ""
            if tok:
                if first:
                    kill_spinner()
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
                if i not in tcs: tcs[i]={"id":"","name":"","args":""}
                if tc.get("id"): tcs[i]["id"]+=tc["id"]
                f=tc.get("function",{})
                if f.get("name"): tcs[i]["name"]+=f["name"]
                if f.get("arguments"): tcs[i]["args"]+=f["arguments"]
except KeyboardInterrupt:
    was_interrupted=True
    kill_spinner()
    tty.write("\n    \033[38;5;196m[Cancelled by User]\033[0m\n")
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
msg={"role":"assistant","content":full}
if tcs:
    msg["tool_calls"]=[{"id":tcs[i]["id"],"type":"function",
        "function":{"name":tcs[i]["name"],"arguments":tcs[i]["args"]}}
        for i in sorted(tcs)]
if not full: msg["content"]=""
sys.stdout.write("RAW:"+base64.b64encode(json.dumps(msg).encode()).decode()+"\n")
if tcs:
    for i in sorted(tcs): sys.stdout.write("TC:"+tcs[i]["id"]+"|||"+tcs[i]["name"]+"|||"+tcs[i]["args"]+"\n")
if full:
    sys.stdout.write("TEXT:"+full+"\n")
elif not tcs:
    sys.stdout.write("TEXT:(empty)\n")
sys.stdout.flush()
' <<< "$payload" > "$tmp_out"

  local result; result=$(cat "$tmp_out"); rm -f "$tmp_out"
  [ -z "$result" ] && { echo "FAIL:stream"; return 1; }
  printf '%s' "$result"
}

