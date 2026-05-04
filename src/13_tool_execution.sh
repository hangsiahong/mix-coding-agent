# ─── Tool Execution ─────────────────────────────────────────────────────────
run_tool() {
  local name="$1" args="$2" result=""

  case "$name" in
    bash)
      local cmd
      cmd=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      result=$(bash -c "$cmd" 2>&1)
      local _ec=$?
      [ $_ec -ne 0 ] && result="[FAILED exit=$_ec]
$result"
      ;;
    bash_with_heal)
      local cmd
      cmd=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      result=$(run_with_heal "$cmd")
      ;;
    read_file)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      [ ! -f "$path" ] && { echo "Error: not found: $path"; return; }
      result=$(cat "$path" 2>&1) || true
      [ ${#result} -gt 10000 ] && result="${result:0:10000}\n...[truncated]"
      # Cache file content for session — survives compaction
      file_cache_put "$path" "$result" 2>/dev/null || true
      ;;
    edit_file)
      local _ea_dir; _ea_dir=$(mktemp -d -t mix-XXXXXX)
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
      [ ! -f "$path" ] && { echo "Error: not found: $path"; return; }
      # Detect external file modification since last cache read
      if [ "$AUTO_VERIFY" != "off" ]; then
        local _cached_mtime
        _cached_mtime=$(printf '%s' "$_FILE_CACHE" | python3 -c "import json,sys;c=json.load(sys.stdin).get('$path',{});print(c.get('mtime',0))" 2>/dev/null) || _cached_mtime=0
        if [ "$_cached_mtime" != "0" ]; then
          local _current_mtime; _current_mtime=$(stat -c '%Y' "$path" 2>/dev/null) || echo "0"
          if [ "$_current_mtime" != "$_cached_mtime" ] && [ "$_current_mtime" != "0" ]; then
            echo "Warning: file modified externally since last read. Consider re-reading before editing."
          fi
        fi
      fi
      result=$(python3 -c "
import sys, re
p,o,n=sys.argv[1],sys.argv[2],sys.argv[3]
content=open(p).read()

def normalize(s):
    return '\n'.join(line.rstrip() for line in s.replace('\r\n','\n').replace('\r','\n').split('\n'))

def strip_indent(s):
    return '\n'.join(line.lstrip() for line in s.split('\n'))

# 1. Exact match
count=content.count(o)
if count == 1:
    open(p,'w').write(content.replace(o,n,1))
    print('Edited '+p)
    sys.exit(0)
if count > 1:
    print('Error: old_text not unique ('+str(count)+' matches) in '+p)
    sys.exit(0)

# 2. Fuzzy match: normalize trailing whitespace + line endings
nc = normalize(content)
no = normalize(o)
if no in nc:
    fcount = nc.count(no)
    if fcount == 1:
        # We apply the edit to the normalized version. 
        # This is safe because normalize() only removes \r and trailing spaces.
        open(p,'w').write(nc.replace(no, normalize(n), 1))
        print('Edited '+p+' (fuzzy whitespace match)')
        sys.exit(0)
    if fcount > 1:
        print('Error: fuzzy old_text match not unique ('+str(fcount)+' matches) in '+p)
        sys.exit(0)

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
    open(p,'w').write('\n'.join(new_nc))
    print('Edited '+p+' (fuzzy indent match)')
    sys.exit(0)

# 4. Fallback: Block Header/Footer Anchor match
# If old_text has multiple lines, try matching first and last lines uniquely
o_lines = [l.strip() for l in no.split('\n') if l.strip()]
if len(o_lines) > 2:
    first, last = o_lines[0], o_lines[-1]
    nc_lines = nc.split('\n')
    matches = []
    for i, line in enumerate(nc_lines):
        if first in line:
            # Look ahead for the last line within a reasonable range (len(o_lines) + 10)
            for j in range(i + 1, min(i + len(o_lines) + 10, len(nc_lines))):
                if last in nc_lines[j]:
                    matches.append((i, j))
    if len(matches) == 1:
        i, j = matches[0]
        new_nc = nc_lines[:i] + [normalize(n)] + nc_lines[j+1:]
        open(p,'w').write('\n'.join(new_nc))
        print('Edited '+p+' (anchor match: lines '+str(i+1)+'-'+str(j+1)+')')
        sys.exit(0)

print('Error: old_text not found in '+p)
" "$path" "$old_text" "$new_text")
      # Update file cache after successful edit
      if [[ "$result" == Edited* ]] && [ -f "$path" ]; then
        local _new_content; _new_content=$(cat "$path" 2>/dev/null) || true
        [ -n "$_new_content" ] && file_cache_put "$path" "$_new_content" 2>/dev/null || true
        # Auto-verify: syntax/lint/typecheck
        local _vout; _vout=$(auto_verify "$path" 2>/dev/null) || true
        [ -n "$_vout" ] && result+="$_vout"
      fi
      ;;
    list_files)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      [ ! -d "$path" ] && { echo "Error: not a dir: $path"; return; }
      result=$(ls -F --color=never "$path" 2>&1) || true
      ;;
    create_file)
      result=$(printf '%s' "$args" | python3 -c '
import json,sys,os
d=json.load(sys.stdin)
p=d["path"]
if os.path.exists(p):
    print("Error: file already exists: "+p+" (use edit_file to modify)")
    sys.exit(0)
os.makedirs(os.path.dirname(p) or ".",exist_ok=True)
open(p,"w").write(d["content"])
print("Created "+p+" ("+str(len(d["content"].splitlines()))+" lines)")
' 2>/dev/null) || result="Error: bad args"
      # Cache newly created file
      if [[ "$result" == Created* ]]; then
        local _cfp _cfc
        _cfp=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null)
        _cfc=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["content"])' 2>/dev/null)
        [ -n "$_cfp" ] && [ -n "$_cfc" ] && file_cache_put "$_cfp" "$_cfc" 2>/dev/null || true
        # Auto-verify: syntax/lint/typecheck
        local _vout; _vout=$(auto_verify "$_cfp" 2>/dev/null) || true
        [ -n "$_vout" ] && result+="$_vout"
      fi
      ;;
    search_files)
      local _sf_pat _sf_path
      _sf_pat=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pattern"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      _sf_path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
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
        result="Global memory updated: + $(printf '%s' "$_gm_content" | head -c 80)"
      elif [ "$_gm_action" = "replace" ]; then
        _gm_old=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("old_text",""))' 2>/dev/null) || { echo "Error: bad args"; return; }
        if [ -f "$_gmem" ] && grep -qF "$_gm_old" "$_gmem"; then
          result=$(python3 -c '
import sys
old,new,path=sys.argv[1],sys.argv[2],sys.argv[3]
content=open(path).read()
if old not in content: print("Error: old_text not found"); sys.exit(0)
open(path,"w").write(content.replace(old,new,1))
print("Global memory updated.")
' "$_gm_old" "$_gm_content" "$_gmem" 2>/dev/null) || result="Error updating global memory"
        else
          result="Error: old_text not found in global memory"
        fi
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
        _sa_tmp=$(mktemp -t mix-XXXXXX)
        _sa_tty=$(tty 2>/dev/null || echo /dev/null)
        printf '%s\n' "$_sa_task" > "$_sa_tmp"
        tmux new-window -n "$_sa_name" "bash -c 'cat $_sa_tmp | mix 2>&1 | tee /tmp/${_sa_name}.log; rm -f $_sa_tmp; echo -e \"\n  \033[38;5;82m✓ Subagent [${_sa_name}] finished!\033[0m (read /tmp/${_sa_name}.log)\" > $_sa_tty; echo \"\"; echo \"[Subagent done. Press Enter to close]\"; read -r'" 2>/dev/null \
          && result="Subagent [$_sa_name] spawned. Output → /tmp/${_sa_name}.log" \
          || result="Error: failed to spawn subagent (tmux new-window failed)"
      fi
      ;;
    *) result="Unknown tool: $name" ;;
  esac
  [ -z "$result" ] && result="(no output)"
  printf '%s' "$result"
}

