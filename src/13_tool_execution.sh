# ─── Tool Execution ─────────────────────────────────────────────────────────
run_tool() {
  local name="$1" args="$2" result=""
  case "$name" in
    bash)
      local cmd
      cmd=$(printf '%s' "$args" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || { echo "Error: bad args"; return; }
      result=$(eval "$cmd" 2>&1)
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
      local _ea_dir; _ea_dir=$(mktemp -d)
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
      local count; count=$(grep -cF "$old_text" "$path" || true)
      if [ "$count" -eq 0 ]; then echo "Error: old_text not found in $path"
      elif [ "$count" -gt 1 ]; then echo "Error: old_text not unique ($count matches) in $path"
      else
        python3 -c "
import sys
p,o,n=sys.argv[1],sys.argv[2],sys.argv[3]
c=open(p).read().replace(o,n,1)
open(p,'w').write(c)
print('Edited '+p)
" "$path" "$old_text" "$new_text"
      fi
      return
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
      result=$(grep -rn -E "$_sf_pat" "$_sf_path" \
        --include='*.sh' --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' \
        --include='*.py' --include='*.go' --include='*.rs' --include='*.md' \
        --include='*.json' --include='*.yaml' --include='*.yml' \
        --include='*.html' --include='*.css' --include='*.txt' --include='*.toml' \
        2>/dev/null | head -60) || true
      [ -z "$result" ] && result="(no matches for: $_sf_pat)"
      ;;
    *) result="Unknown tool: $name" ;;
  esac
  [ -z "$result" ] && result="(no output)"
  printf '%s' "$result"
}

