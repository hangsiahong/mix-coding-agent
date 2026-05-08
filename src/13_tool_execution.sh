# ─── Tool Execution ─────────────────────────────────────────────────────────

# Sandbox path guard — in sandbox mode, file tools are restricted to mounted paths only.
# Allowed: $WORKDIR (project) and $HOME/.mix (agent state).
_sandbox_path_allowed() {
  local p="$1"
  # Resolve to real path (handle symlinks, .., etc.)
  local real; real=$(_mix_realpath "$p")
  local wd; wd=$(_mix_realpath "${WORKDIR:-$PWD}")
  local md; md=$(_mix_realpath "${HOME}/.mix")
  [[ "$real" == "$wd"* ]] || [[ "$real" == "$md"* ]]
}

# Detect commands that must run on the host (not inside sandbox).
# - All git commands: git needs /tmp for temp files; sandbox /tmp is empty.
#   Also git push/pull/fetch need host network.
# - Package managers that need network: npm install, pip install, etc.
# - Direct network tools: curl, wget.
# In sandbox mode these are transparently routed to the host (run in $WORKDIR).
# Handles prefixes like: cd /workspace && git push, env VAR=x git push, etc.
_sandbox_needs_host_network() {
  local cmd="$1"
  # Strip common prefixes: 'cd /workspace &&', 'cd /workspace;', env var assignments
  local c; c=$(printf '%s' "$cmd" | sed 's|cd[[:space:]]*/workspace[[:space:]]*&&[[:space:]]*||g; s|cd[[:space:]]*/workspace[[:space:]]*;[[:space:]]*||g; s/^[[:space:]]*//')
  # Also strip any leading env var assignments (VAR=val cmd)
  while [[ "$c" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    c="${c#*=}"; c="${c#* }"
  done
  case "$c" in
    git\ *) return 0 ;;
    npm\ publish*|npm\ install*|yarn\ install*|pip\ install*|pip3\ install*) return 0 ;;
    curl\ *|wget\ *) return 0 ;;
  esac
  return 1
}

run_tool() {
  local name="$1" args="$2" result=""

  case "$name" in
    bash)
      local cmd bg
      cmd=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      bg=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("background",False))' 2>/dev/null)
      
      if [ "$bg" = "True" ]; then
        local jid; jid="job-$RANDOM"
        local log="/tmp/mix-$jid.log"
        if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
           # For simplicity, background jobs in sandbox use nohup
           (sandbox_run_cmd "$cmd" >"$log" 2>&1) &
        else
           (bash -c "$cmd" >"$log" 2>&1) &
        fi
        result="Background job started. ID: $jid. Check output with check_job."
      else
        if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
          if _sandbox_needs_host_network "$cmd"; then
            result=$(cd "${WORKDIR:-$PWD}" && bash -c "$cmd" </dev/null 2>&1)
            result="[host] $result"
          else
            result=$(sandbox_run_cmd "$cmd" </dev/null)
          fi
        else
          result=$(bash -c "$cmd" </dev/null 2>&1)
        fi
        local _ec=$?
        if [ ${#result} -gt 16000 ]; then
          result="${result:0:4000}\n\n...[TRUNCATED MIDDLE]...\n\n${result: -12000}"
        fi
        [ $_ec -ne 0 ] && result="[FAILED exit=$_ec]
$result"
      fi
      ;;
    send_message)
      local to msg
      to=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["to"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      msg=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["message"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      local bus_dir="${WORKDIR:-$PWD}/.mix/bus"
      mkdir -p "$bus_dir"
      # Append message to target mailbox
      local box="$bus_dir/${to}.jsonl"
      printf '{"from": "%s", "time": %s, "msg": %s}\n' \
        "${AGENT_NAME:-main}" "$(date +%s)" "$(printf '%s' "$msg" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
        >> "$box"
      result="Message sent to $to."
      ;;
    read_messages)
      local bus_dir="${WORKDIR:-$PWD}/.mix/bus"
      local my_name="${AGENT_NAME:-main}"
      local box="$bus_dir/${my_name}.jsonl"
      if [ -f "$box" ]; then
        result=$(cat "$box")
        # Clear box after reading? Or keep? Let's rename to archive to clear.
        mv "$box" "${box}.old"
      else
        result="No new messages for $my_name."
      fi
      ;;
    find_definition)
      local sym; sym=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["symbol"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      _detect_ctags
      if [ -z "$_CTAGS_EXE" ]; then
        # Fallback to grep for common definition patterns
        result=$(grep -rnE "(def |class |fn |function |struct |interface )$sym" . --exclude-dir=.git --exclude-dir=node_modules | head -10)
        [ -z "$result" ] && result="Symbol '$sym' not found (ctags missing, grep failed)."
      else
        # Use ctags
        result=$("$_CTAGS_EXE" --output-format=json --fields=+nS -R . 2>/dev/null | python3 -c '
import json,sys
sym = sys.argv[1]
matches = []
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get("name") == sym:
            matches.append(f"{d.get(\"path\")}:{d.get(\"line\")}")
    except: continue
if matches: print("\n".join(matches[:10]))
' "$sym")
        [ -z "$result" ] && result="Symbol '$sym' not found via ctags."
      fi
      ;;
    check_job)
      local jid; jid=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["job_id"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      local log="/tmp/mix-$jid.log"
      if [ ! -f "$log" ]; then
        result="Error: job log not found: $log"
      else
        # Check if process still running — hard to do accurately without PID, but we can check log age or look for marker
        # We will just return the tail of the log
        result=$(tail -n 100 "$log")
        [ -z "$result" ] && result="(job started but no output yet)"
      fi
      ;;
    bash_with_heal)
      local cmd bg
      cmd=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      bg=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("background",False))' 2>/dev/null)
      
      if [ "$bg" = "True" ]; then
        local jid; jid="job-$RANDOM"
        local log="/tmp/mix-$jid.log"
        (bash -c "$cmd" >"$log" 2>&1) &
        result="Background job started. ID: $jid. Check output with check_job."
      else
        if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
          if _sandbox_needs_host_network "$cmd"; then
            result=$(cd "${WORKDIR:-$PWD}" && bash -c "$cmd" </dev/null 2>&1)
            result="[host] $result"
          else
            result=$(sandbox_run_cmd "$cmd" </dev/null)
          fi
        else
          result=$(bash -c "$cmd" </dev/null 2>&1)
        fi
        if [ ${#result} -gt 16000 ]; then
          result="${result:0:4000}\n\n...[TRUNCATED MIDDLE]...\n\n${result: -12000}"
        fi
      fi
      ;;
    read_file)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "${SANDBOX_ENABLED:-false}" = "true" ] && ! _sandbox_path_allowed "$path"; then
        echo "Error: sandbox mode — read_file restricted to project dir and ~/.mix. Path outside allowed zone: $path"; return
      fi
      [ ! -f "$path" ] && { echo "Error: not found: $path"; return; }
      result=$(cat "$path" 2>&1) || true
      [ ${#result} -gt 10000 ] && result="${result:0:10000}\n...[truncated]"
      # Cache file content for session — survives compaction
      file_cache_put "$path" "$result" 2>/dev/null || true
      _sysprompt_invalidate  # file cache changed → rebuild sysprompt next call
      ;;
    edit_file)
      local _ea_dir; _ea_dir=$(mktemp -d -t mix-$$-XXXXXX)
      printf '%s' "$args" | python3 -c '
import json,sys,os
d=json.load(sys.stdin);b=sys.argv[1]
open(os.path.join(b,"p"),"w").write(d["path"])
open(os.path.join(b,"o"),"w").write(d["old_text"])
open(os.path.join(b,"n"),"w").write(d["new_text"])
' "$_ea_dir" 2>/dev/null || { rm -rf "$_ea_dir"; echo "Error: bad args"; return; }
      local path old_text new_text
      path=$(cat "$_ea_dir/p"); old_text=$(cat "$_ea_dir/o"); new_text=$(cat "$_ea_dir/n")
      rm -rf "$_ea_dir"
      if [ "${SANDBOX_ENABLED:-false}" = "true" ] && ! _sandbox_path_allowed "$path"; then
        echo "Error: sandbox mode — edit_file restricted to project dir and ~/.mix. Path outside allowed zone: $path"; return
      fi
      [ ! -f "$path" ] && { echo "Error: not found: $path"; return; }
      # Detect external file modification since last cache read
      if [ "$AUTO_VERIFY" != "off" ]; then
        local _cached_mtime
        _cached_mtime=$(printf '%s' "$_FILE_CACHE" | python3 -c "import json,sys;c=json.load(sys.stdin).get('$path',{});print(c.get('mtime',0))" 2>/dev/null) || _cached_mtime=0
        if [ "$_cached_mtime" != "0" ]; then
          local _current_mtime; _current_mtime=$(_mix_stat_mtime "$path")
          if [ "$_current_mtime" != "$_cached_mtime" ] && [ "$_current_mtime" != "0" ]; then
            echo "Warning: file modified externally since last read. Consider re-reading before editing."
          fi
        fi
      fi
      result=$(python3 -c "
import sys, re, os
p,o,n=sys.argv[1],sys.argv[2],sys.argv[3]
content=open(p).read()

def normalize(s):
    return '\n'.join(line.rstrip() for line in s.replace('\r\n','\n').replace('\r','\n').split('\n'))

def strip_indent(s):
    return '\n'.join(line.lstrip() for line in s.split('\n'))

def suggest_context(content, old_text, reason):
    lines = content.split(chr(10))
    o_lines = old_text.strip().split(chr(10))
    o_first = o_lines[0].strip() if o_lines else ''
    suggestions = []
    if 'not unique' in reason:
        for i, line in enumerate(lines):
            if o_first and o_first in line:
                start = max(0, i-1)
                end = min(len(lines), i+min(len(o_lines),3)+1)
                ctx = chr(10).join(f'{j+1}: {lines[j]}' for j in range(start, end))
                suggestions.append(f'Match at line {i+1}:{chr(10)}{ctx}')
                if len(suggestions) >= 3: break
    else:
        if o_first:
            found = False
            for i, line in enumerate(lines):
                if o_first in line:
                    start = max(0, i-1)
                    end = min(len(lines), i+min(len(o_lines),3)+1)
                    ctx = chr(10).join(f'{j+1}: {lines[j]}' for j in range(start, end))
                    suggestions.append(f'Found similar at line {i+1}:{chr(10)}{ctx}')
                    found = True
                    break
            if not found:
                ctx = chr(10).join(f'{i+1}: {lines[i]}' for i in range(min(5, len(lines))))
                suggestions.append(f'File starts with:{chr(10)}{ctx}')
        elif len(lines) > 0:
            ctx = chr(10).join(f'{i+1}: {lines[i]}' for i in range(min(5, len(lines))))
            suggestions.append(f'File starts with:{chr(10)}{ctx}')
    if suggestions:
        combined = chr(10).join(suggestions)[:500]
        sys.stderr.write(chr(10) + '[SUGGESTION] ' + combined + chr(10))

new_content = None
msg = ''

# 1. Exact match
count=content.count(o)
if count == 1:
    new_content = content.replace(o,n,1)
    msg = 'Edited '+p
elif count > 1:
    print('Error: old_text not unique ('+str(count)+' matches) in '+p)
    suggest_context(content, o, 'not unique')
    sys.exit(0)
else:
    # 2. Fuzzy match
    nc = normalize(content)
    no = normalize(o)
    if no in nc:
        fcount = nc.count(no)
        if fcount == 1:
            new_content = nc.replace(no, normalize(n), 1)
            msg = 'Edited '+p+' (fuzzy whitespace match)'
        elif fcount > 1:
            print('Error: fuzzy old_text match not unique ('+str(fcount)+' matches) in '+p)
            suggest_context(content, o, 'not unique')
            sys.exit(0)
    else:
        # 3. Indent-agnostic match
        sc = strip_indent(nc)
        so = strip_indent(no)
        icount = sc.count(so)
        if icount == 1:
            idx = sc.index(so)
            start_line = sc[:idx].count('\n')
            match_lines = so.count('\n') + 1
            nc_lines = nc.split('\n')
            new_nc = nc_lines[:start_line] + [normalize(n)] + nc_lines[start_line + match_lines:]
            new_content = '\n'.join(new_nc)
            msg = 'Edited '+p+' (fuzzy indent match)'
        else:
            # 4. Fallback: Block Header/Footer Anchor match
            o_lines = [l.strip() for l in no.split('\n') if l.strip()]
            if len(o_lines) > 2:
                first, last = o_lines[0], o_lines[-1]
                nc_lines = nc.split('\n')
                matches = []
                for i, line in enumerate(nc_lines):
                    if first in line:
                        for j in range(i + 1, min(i + len(o_lines) + 10, len(nc_lines))):
                            if last in nc_lines[j]:
                                matches.append((i, j))
                if len(matches) == 1:
                    i, j = matches[0]
                    new_nc = nc_lines[:i] + [normalize(n)] + nc_lines[j+1:]
                    new_content = '\n'.join(new_nc)
                    msg = 'Edited '+p+' (anchor match: lines '+str(i+1)+'-'+str(j+1)+')'

if new_content is not None:
    # Write potential new content to a temp file for bash to handle
    with open(p + '.next', 'w') as f:
        f.write(new_content)
    print(msg)
else:
    print('Error: old_text not found in '+p)
    suggest_context(content, o, 'not found')
" "$path" "$old_text" "$new_text")

      if [[ "$result" == Edited* ]] && [ -f "$path.next" ]; then
        mv "$path.next" "$path"
      fi

      # Update file cache after successful edit
      if [[ "$result" == Edited* ]] && [ -f "$path" ]; then
        local _new_content; _new_content=$(cat "$path" 2>/dev/null) || true
        [ -n "$_new_content" ] && file_cache_put "$path" "$_new_content" 2>/dev/null || true
        _sysprompt_invalidate  # file cache changed → rebuild sysprompt next call
        # Auto-verify: syntax/lint/typecheck
        local _vout; _vout=$(auto_verify "$path" 2>/dev/null) || true
        [ -n "$_vout" ] && result+="$_vout"
      fi
      ;;
    list_files)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "${SANDBOX_ENABLED:-false}" = "true" ] && ! _sandbox_path_allowed "$path"; then
        echo "Error: sandbox mode — list_files restricted to project dir and ~/.mix. Path outside allowed zone: $path"; return
      fi
      [ ! -d "$path" ] && { echo "Error: not a dir: $path"; return; }
      result=$(ls -F --color=never "$path" 2>&1) || true
      ;;
    delete_file)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "${SANDBOX_ENABLED:-false}" = "true" ] && ! _sandbox_path_allowed "$path"; then
        echo "Error: sandbox mode — delete_file restricted to project dir. Path: $path"; return
      fi
      if [ -f "$path" ]; then
        rm "$path" && result="Deleted $path" || result="Error: failed to delete $path"
        if [[ "$result" == Deleted* ]]; then
          file_cache_del "$path"
          _sysprompt_invalidate
        fi
      else
        result="Error: file not found: $path"
      fi
      ;;
    move_file)
      local src dst
      src=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["source"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      dst=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["destination"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
        if ! _sandbox_path_allowed "$src" || ! _sandbox_path_allowed "$dst"; then
          echo "Error: sandbox mode — move_file restricted to project dir."; return
        fi
      fi
      if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        mv "$src" "$dst" && result="Moved $src to $dst" || result="Error: failed to move $src"
        if [[ "$result" == Moved* ]]; then
          # Update cache: remove old, put new (if we have content)
          # We check if old path was in cache by grep
          if printf '%s' "$_FILE_CACHE" | grep -qF "\"$src\""; then
             # Extract content from old cache entry
             local _content; _content=$(printf '%s' "$_FILE_CACHE" | python3 -c "import json,sys;print(json.load(sys.stdin).get('$src',{}).get('content',''))" 2>/dev/null)
             file_cache_del "$src"
             [ -n "$_content" ] && file_cache_put "$dst" "$_content"
          fi
          _sysprompt_invalidate
        fi
      else
        result="Error: source file not found: $src"
      fi
      ;;
    create_files)
      # args is {"files": {"path": "content", ...}}
      result=$(python3 -c '
import json, sys, os
try:
    args = json.load(sys.stdin)
    files = args.get("files", {})
    created = []
    errors = []
    for path, content in files.items():
        if os.path.exists(path):
            errors.append(f"Error: already exists: {path}")
            continue
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)
            created.append(path)
        except Exception as e:
            errors.append(f"Error: {path}: {str(e)}")
    
    if created:
        print("Created files: " + ", ".join(created))
    if errors:
        print("\n".join(errors))
except Exception as e:
    print(f"Error parsing create_files args: {str(e)}")
' <<< "$args" 2>/dev/null)
      
      # Update cache for all successfully created files
      # We extract paths from the result string "Created files: path1, path2..."
      if [[ "$result" == Created\ files:* ]]; then
        local _paths_str="${result%%Error:*}"
        _paths_str="${_paths_str#Created files: }"
        IFS=', ' read -r -a _paths_arr <<< "$_paths_str"
        for _p in "${_paths_arr[@]}"; do
           # We need to get the content back from the args JSON to put in cache
           local _c; _c=$(printf '%s' "$args" | python3 -c "import json,sys;print(json.load(sys.stdin)['files'].get('$(_mix_realpath "$_p")',''))" 2>/dev/null)
           [ -n "$_c" ] && file_cache_put "$_p" "$_c" 2>/dev/null
        done
        _sysprompt_invalidate
      fi
      ;;
    create_file)
      if [ "${SANDBOX_ENABLED:-false}" = "true" ]; then
        local _cfpath; _cfpath=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null)
        if ! _sandbox_path_allowed "$_cfpath"; then
          echo "Error: sandbox mode — create_file restricted to project dir and ~/.mix. Path outside allowed zone: $_cfpath"; return
        fi
      fi
      result=$(printf '%s' "$args" | python3 -c '
import json,sys,os
d=json.load(sys.stdin)
p=d["path"]
if os.path.exists(p):
    print("Error: file already exists: "+p+" (use edit_file to modify)")
    sys.exit(0)
# Instead of writing, we write to .next
os.makedirs(os.path.dirname(p) or ".",exist_ok=True)
with open(p + ".next", "w") as f:
    f.write(d["content"])
print("Created "+p+" ("+str(len(d["content"].splitlines()))+" lines)")
' 2>/dev/null) || result="Error: bad args"

      if [[ "$result" == Created* ]]; then
        local _cfp; _cfp=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null)
        if [ -f "$_cfp.next" ]; then
           mv "$_cfp.next" "$_cfp"
        fi
      fi

      # Cache newly created file
      if [[ "$result" == Created* ]]; then
        local _cfp _cfc
        _cfp=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null)
        _cfc=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["content"])' 2>/dev/null)
        [ -n "$_cfp" ] && [ -n "$_cfc" ] && file_cache_put "$_cfp" "$_cfc" 2>/dev/null || true
        _sysprompt_invalidate  # file cache changed → rebuild sysprompt next call
        # Auto-verify: syntax/lint/typecheck
        local _vout; _vout=$(auto_verify "$_cfp" 2>/dev/null) || true
        [ -n "$_vout" ] && result+="$_vout"
      fi
      ;;
    search_files)
      local _sf_pat _sf_path
      _sf_pat=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pattern"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      _sf_path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "${SANDBOX_ENABLED:-false}" = "true" ] && ! _sandbox_path_allowed "$_sf_path"; then
        echo "Error: sandbox mode — search_files restricted to project dir and ~/.mix. Path outside allowed zone: $_sf_path"; return
      fi
      [ ! -e "$_sf_path" ] && { echo "Error: not found: $_sf_path"; return; }
      result=$(grep -rn -E -I "$_sf_pat" "$_sf_path" 2>/dev/null | head -60) || true
      [ -z "$result" ] && result="(no matches for: $_sf_pat)"
      ;;
    update_global_memory)
      local _gmem="${HOME}/.mix/memory.md"
      mkdir -p "${HOME}/.mix"
      local _gm_action _gm_content _gm_old
      _gm_action=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("action","append"))' 2>/dev/null) || _gm_action="append"
      _gm_content=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("content",""))' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ "$_gm_action" = "append" ]; then
        [ ! -f "$_gmem" ] && printf '# Global Memory\n\n' > "$_gmem"
        printf '%s\n' "- $_gm_content" >> "$_gmem"
        # Auto-consolidate when file exceeds budget (4000 chars).
        # Keeps the most recent entries + merges related older ones into summary bullets.
        # This prevents unbounded growth — the injection cap (2000 chars) only truncates
        # at read time; this actually reduces the file size.
        local _GMEM_FILE_BUDGET=4000
        local _gm_size; _gm_size=$(wc -c < "$_gmem" 2>/dev/null) || _gm_size=0
        if [ "$_gm_size" -gt "$_GMEM_FILE_BUDGET" ]; then
          # Keep last 10 bullets verbatim, drop older ones
          local _gm_new
          _gm_new=$(python3 -c '
import sys
lines = open(sys.argv[1]).read().rstrip().split("\n")
header = []
bullets = []
for l in lines:
    if l.startswith("#") or l.strip() == "":
        if not bullets: header.append(l)
    elif l.startswith("- "):
        bullets.append(l)
# Keep last 15 bullets — gives some room before next consolidation
keep = bullets[-15:] if len(bullets) > 15 else bullets
print("\n".join(header + [""] + keep))
' "$_gmem" 2>/dev/null) || _gm_new=""
          if [ -n "$_gm_new" ]; then
            printf '%s\n' "$_gm_new" > "$_gmem"
            _gm_size=$(wc -c < "$_gmem" 2>/dev/null) || _gm_size=0
          fi
        fi
        result="Global memory updated: + $(printf '%s' "$_gm_content" | head -c 80) (${_gm_size}b)"
      elif [ "$_gm_action" = "replace" ]; then
        _gm_old=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("old_text",""))' 2>/dev/null) || { echo "Error: bad args"; return; }
        if [ -f "$_gmem" ]; then
          # Use python for both the existence check and the replacement — avoids
          # grep misinterpreting old_text content as flags (e.g. leading dashes, backticks)
          result=$(printf '%s' "$args" | python3 -c '
import json,sys
d = json.load(sys.stdin)
old, new, path = d["old_text"], d["content"], sys.argv[1]
content = open(path).read()
if old not in content:
    print("Error: old_text not found in global memory")
else:
    open(path, "w").write(content.replace(old, new, 1))
    print("Global memory updated.")
' "$_gmem" 2>/dev/null) || result="Error updating global memory"
        else
          result="Error: global memory file not found"
        fi
      fi
      ;;
    send_message)
      local to msg
      to=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["to"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      msg=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["message"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      local bus_dir="${WORKDIR:-$PWD}/.mix/bus"
      mkdir -p "$bus_dir"
      # Append message to target mailbox
      local box="$bus_dir/${to}.jsonl"
      printf '{"from": "%s", "time": %s, "msg": %s}\n' \
        "${AGENT_NAME:-main}" "$(date +%s)" "$(printf '%s' "$msg" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
        >> "$box"
      result="Message sent to $to."
      ;;
    read_messages)
      local bus_dir="${WORKDIR:-$PWD}/.mix/bus"
      local my_name="${AGENT_NAME:-main}"
      local box="$bus_dir/${my_name}.jsonl"
      if [ -f "$box" ]; then
        result=$(cat "$box")
        # Clear box after reading? Or keep? Let's rename to archive to clear.
        mv "$box" "${box}.old"
      else
        result="No new messages for $my_name."
      fi
      ;;
    find_definition)
      local sym; sym=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["symbol"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      _detect_ctags
      if [ -z "$_CTAGS_EXE" ]; then
        # Fallback to grep for common definition patterns
        result=$(grep -rnE "(def |class |fn |function |struct |interface )$sym" . --exclude-dir=.git --exclude-dir=node_modules | head -10)
        [ -z "$result" ] && result="Symbol '$sym' not found (ctags missing, grep failed)."
      else
        # Use ctags
        result=$("$_CTAGS_EXE" --output-format=json --fields=+nS -R . 2>/dev/null | python3 -c '
import json,sys
sym = sys.argv[1]
matches = []
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get("name") == sym:
            matches.append(f"{d.get(\"path\")}:{d.get(\"line\")}")
    except: continue
if matches: print("\n".join(matches[:10]))
' "$sym")
        [ -z "$result" ] && result="Symbol '$sym' not found via ctags."
      fi
      ;;
    spawn_subagent)
      local _sa_name _sa_task _sa_tmp _sa_tty
      _sa_name=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("name",""))' 2>/dev/null) || { echo "Error: bad args"; return; }
      _sa_task=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("task",""))' 2>/dev/null) || { echo "Error: bad args"; return; }
      if [ -z "$TMUX" ]; then
        result="Error: not in tmux — cannot spawn subagent"
      elif [ -z "$_sa_name" ] || [ -z "$_sa_task" ]; then
        result="Error: name and task are required"
      else
        mkdir -p "${WORKDIR}/.mix/bus"
        _sa_tmp=$(mktemp -t mix-$$-XXXXXX)
        _sa_tty=$(tty 2>/dev/null || echo /dev/null)
        printf '%s\n' "$_sa_task" > "$_sa_tmp"
        tmux new-window -d -n "$_sa_name" "bash -c 'cat $_sa_tmp | mix 2>&1 | tee /tmp/${_sa_name}.log; rm -f $_sa_tmp; echo -e \"\n  \033[38;5;82m$I_OK Subagent [${_sa_name}] finished!\033[0m (read /tmp/${_sa_name}.log)\" > $_sa_tty; echo \"\"; echo \"[Subagent done. Press Enter to close]\"; read -r'" 2>/dev/null \
        result="Subagent [$_sa_name] spawned. Output → /tmp/${_sa_name}.log. (Use .mix/bus/ to share data)" \
          || result="Error: failed to spawn subagent (tmux new-window failed)"
      fi
      ;;
    *)
      if _ext_dispatch_tool "$name" "$args" > /tmp/ext_result; then
         result=$(cat /tmp/ext_result)
         rm /tmp/ext_result
      else
         result="Unknown tool: $name"
      fi
      ;;
  esac
  [ -z "$result" ] && result="(no output)"
  printf '%s' "$result"
}
