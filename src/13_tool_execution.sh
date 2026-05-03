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
    read_file)
      local path
      path=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      [ ! -f "$path" ] && { echo "Error: not found: $path"; return; }
      result=$(cat "$path" 2>&1) || true
      [ ${#result} -gt 10000 ] && result="${result:0:10000}\n...[truncated]"
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
      result=$(python3 -c "
import sys, re
p,o,n=sys.argv[1],sys.argv[2],sys.argv[3]
content=open(p).read()

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
def normalize(s):
    return '\n'.join(line.rstrip() for line in s.replace('\r\n','\n').replace('\r','\n').split('\n'))

nc = normalize(content)
no = normalize(o)
fcount = nc.count(no)
if fcount == 1:
    # Find the span in normalized content, map replacement back
    idx = nc.index(no)
    # Rebuild: prefix + new_text normalized + suffix
    open(p,'w').write(nc[:idx] + normalize(n) + nc[idx+len(no):])
    print('Edited '+p+' (fuzzy whitespace match)')
    sys.exit(0)
if fcount > 1:
    print('Error: old_text not unique after fuzzy match ('+str(fcount)+' matches) in '+p)
    sys.exit(0)

# 3. Indent-agnostic match: strip all leading whitespace per line
def strip_indent(s):
    return '\n'.join(line.lstrip() for line in s.split('\n'))

sc = strip_indent(nc)
so = strip_indent(no)
icount = sc.count(so)
if icount == 1:
    # Apply: find the actual region in normalized content and replace
    idx = sc.index(so)
    # Corrected: we need the length of the matching segment in the *normalized* string, 
    # not the stripped string, to slice correctly.
    # Actually, easier: find start/end indices in sc, map to nc.
    start_line = sc[:idx].count('\n')
    match_lines = so.count('\n') + 1
    nc_lines = nc.split('\n')
    new_nc = nc_lines[:start_line] + [normalize(n)] + nc_lines[start_line + match_lines:]
    open(p,'w').write('\n'.join(new_nc))
    print('Edited '+p+' (fuzzy indent match)')
    sys.exit(0)
if icount > 1:
    print('Error: old_text not unique after indent-agnostic match ('+str(icount)+' matches) in '+p)
    sys.exit(0)

print('Error: old_text not found in '+p)
" "$path" "$old_text" "$new_text")
      #return
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
    *) result="Unknown tool: $name" ;;
  esac
  [ -z "$result" ] && result="(no output)"
  printf '%s' "$result"
}

