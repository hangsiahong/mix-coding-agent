# ─── Streaming API call ───────────────────────────────────────────────────────
# Streams content tokens live to /dev/tty. Returns same RAW/TC/TEXT format.
call_api_stream() {
  local payload
  payload=$(_api_build_payload "true") || { echo "FAIL:payload"; return 1; }

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

  local tmp_out; tmp_out=$(mktemp -t mix-$$-XXXXXX)
  
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
                
                # Google OpenAI-compat preview models might stream it at root or under extra_content
                _ts = tc.get("thought_signature")
                if not _ts and tc.get("extra_content", {}).get("google", {}).get("thought_signature"):
                    _ts = tc["extra_content"]["google"]["thought_signature"]
                if _ts: tcs[i]["sig"]+=_ts
                
                f=tc.get("function",{})
                if f.get("name"): tcs[i]["name"]+=f["name"]
                if f.get("arguments"): tcs[i]["args"]+=f["arguments"]
except KeyboardInterrupt:
    was_interrupted=True
    kill_spinner()
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
    # ── Table renderer helper ──
    _TABLE_RE = re.compile(r"^\|.*\|$")
    _SEP_RE = re.compile(r"^\|[\s:\-|]+\|$")
    def _parse_table_cell(s):
        """Parse alignment from separator cell: :---: = center, :--- = left, ---: = right"""
        s = s.strip()
        left = s.startswith(":")
        right = s.endswith(":")
        if left and right: return "center"
        if right: return "right"
        return "left"
    def _pad_cell(text, width, align):
        text = text.strip()
        pad = width - len(text)
        if pad <= 0: return text[:width]
        if align == "center":
            l = pad // 2; r = pad - l
            return " " * l + text + " " * r
        elif align == "right":
            return " " * pad + text
        else:
            return text + " " * pad
    def _render_table(rows, rendered_lines):
        """Render collected table rows as a styled box-drawing table."""
        if len(rows) < 2:  # need header + at least separator
            for r in rows:
                rendered_lines.append(r)
            return
        # Parse cells for each row
        parsed = []
        for r in rows:
            cells = [c.strip() for c in r.strip("|").split("|")]
            parsed.append(cells)
        # Get alignments from separator row (row index 1)
        sep_cells = [c.strip() for c in rows[1].strip("|").split("|")]
        aligns = [_parse_table_cell(c) for c in sep_cells]
        # Pad aligns to match max columns
        ncols = max(len(p) for p in parsed)
        while len(aligns) < ncols: aligns.append("left")
        # Pad all rows to ncols
        for p in parsed:
            while len(p) < ncols: p.append("")
        # Compute column widths (strip ANSI for width calc)
        def _strip_ansi(s):
            return re.sub(r"\033\[[0-9;]*m", "", s)
        widths = []
        for ci in range(ncols):
            w = max(len(_strip_ansi(parsed[ri][ci])) for ri in range(len(parsed)))
            widths.append(max(w, 3))  # minimum 3 chars
        DIM = "\033[0;90m"
        RST = "\033[0m"
        BOLD = "\033[1m"
        # Top border
        top = DIM + "  ┌" + "┬".join("─" * (w + 2) for w in widths) + "┐" + RST
        rendered_lines.append(top)
        # Header row (bold)
        hdr_cells = []
        for ci in range(ncols):
            t = _pad_cell(parsed[0][ci], widths[ci], "left")
            hdr_cells.append(" " + BOLD + t + RST + " ")
        mid = DIM + "  ├" + "┼".join("─" * (w + 2) for w in widths) + "┤" + RST
        rendered_lines.append(DIM + "  │" + "│".join(hdr_cells) + "│" + RST)
        rendered_lines.append(mid)
        # Data rows (skip header=0 and separator=1)
        for ri in range(2, len(parsed)):
            row_cells = []
            for ci in range(ncols):
                raw_t = parsed[ri][ci]
                # Apply inline formatting to cell content
                t = raw_t
                t = re.sub(r"\*\*(.+?)\*\*", "\033[1m\\1\033[0m", t)
                t = re.sub(r"`([^`]+)`", "\033[38;5;222m\\1\033[0m", t)
                t = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", "\033[3m\\1\033[0m", t)
                # Pad using stripped length
                stripped_len = len(_strip_ansi(t))
                pad = widths[ci] - stripped_len
                if pad > 0:
                    al = aligns[ci] if ci < len(aligns) else "left"
                    if al == "center":
                        l = pad // 2; r = pad - l
                        t = " " * l + t + " " * r
                    elif al == "right":
                        t = " " * pad + t
                    else:
                        t = t + " " * pad
                row_cells.append(" " + t + " ")
            rendered_lines.append(DIM + "  │" + "│".join(row_cells) + "│" + RST)
        # Bottom border
        bot = DIM + "  └" + "┴".join("─" * (w + 2) for w in widths) + "┘" + RST
        rendered_lines.append(bot)
    # ── Line-by-line with table accumulation ──
    all_lines = full.split("\n")
    i = 0
    while i < len(all_lines):
        raw_line = all_lines[i]
        # Fenced code blocks
        if raw_line.startswith("```"):
            if not in_code_block:
                in_code_block = True
                code_lang = raw_line[3:].strip()
                rendered_lines.append("\033[0;90m  ┌─" + (f" {code_lang} " if code_lang else "") + "\033[0m")
            else:
                in_code_block = False
                rendered_lines.append("\033[0;90m  └─\033[0m")
            i += 1
            continue
        if in_code_block:
            rendered_lines.append("\033[0;90m  │\033[0m \033[38;5;222m" + raw_line + "\033[0m")
            i += 1
            continue
        # ── Table detection: collect consecutive |...| lines ──
        if _TABLE_RE.match(raw_line):
            table_rows = []
            while i < len(all_lines) and _TABLE_RE.match(all_lines[i]):
                table_rows.append(all_lines[i])
                i += 1
            # Only render as table if we have header + separator + at least 1 data row
            if len(table_rows) >= 3 and any(_SEP_RE.match(r) for r in table_rows[1:3]):
                _render_table(table_rows, rendered_lines)
            elif len(table_rows) >= 2 and _SEP_RE.match(table_rows[1] if len(table_rows) > 1 else ""):
                _render_table(table_rows, rendered_lines)
            else:
                # Not a proper table, just pass through
                for r in table_rows:
                    rendered_lines.append(r)
            continue
        # Headers
        if raw_line.startswith("### "):
            rendered_lines.append("\033[1;36m" + raw_line[4:] + "\033[0m")
            i += 1
            continue
        if raw_line.startswith("## "):
            rendered_lines.append("\033[1;33m" + raw_line[3:] + "\033[0m")
            i += 1
            continue
        if raw_line.startswith("# "):
            rendered_lines.append("\033[1;37m" + raw_line[2:] + "\033[0m")
            i += 1
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
        i += 1
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
    sys.stdout.write("USAGE:"+str(usage.get("prompt_tokens",0))+":"+str(usage.get("completion_tokens",0))+":"+str(usage.get("prompt_tokens_details",{}).get("cached_tokens",0))+"\n")
sys.stdout.flush()
' <<< "$payload" > "$tmp_out"

  local result; result=$(cat "$tmp_out"); rm -f "$tmp_out"
  [ -z "$result" ] && { echo "FAIL:stream"; return 1; }
  printf '%s' "$result"
}

