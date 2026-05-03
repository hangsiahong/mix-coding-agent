# ─── Response Parser ─────────────────────────────────────────────────────────
# Returns lines:
#   RAW:<base64 of assistant message object>
#   TC:<id>|||<name>|||<args_json>   per tool call
#   TEXT:<content>            if plain text answer
parse_resp() {
  printf '%s' "$1" | python3 -c '
import json,sys,base64
d=json.load(sys.stdin)
m=d["choices"][0]["message"]
print("RAW:"+base64.b64encode(json.dumps(m).encode()).decode())
if "tool_calls" in m and m["tool_calls"]:
  for tc in m["tool_calls"]:
    f=tc["function"]
    i=tc.get("id","")
    print("TC:"+i+"|||"+f["name"]+"|||"+f["arguments"])
elif m.get("content"):
  print("TEXT:"+m["content"])
else:
  print("TEXT:(empty)")
' 2>/dev/null || echo "FAIL:parse"
}

