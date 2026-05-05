# ─── Pre-edit diff preview ──────────────────────────────────────────────────
show_edit_diff() {
  local targs="$1"
  printf '%s' "$targs" | python3 -c '
import json,sys,os,difflib,re
d=json.load(sys.stdin)
p,o,n=d.get("path","?"),d.get("old_text",""),d.get("new_text","")
GRN,RED,DIM,RST,BOLD="\033[0;32m","\033[0;31m","\033[0;90m","\033[0m","\033[1;37m"
pdir=os.path.dirname(p); pbase=os.path.basename(p)
pdir_s=(DIM+pdir+"/"+RST) if pdir and pdir!="." else ""
if not os.path.exists(p):
    sys.stdout.write("    📝  "+pdir_s+BOLD+pbase+RST+"  "+DIM+"(new file)"+RST+"\n")
    for i,l in enumerate(n.splitlines()[:15],1): sys.stdout.write("    "+GRN+"+ %3d: %s"%(i,l)+RST+"\n")
    if len(n.splitlines())>15: sys.stdout.write("    "+DIM+"... (%d more lines)"+RST+"\n" % (len(n.splitlines())-15))
    sys.exit(0)
content=open(p).read()
if o not in content:
    sys.stdout.write("    ✏️   "+pdir_s+BOLD+pbase+RST+"\n")
    sys.stdout.write("    \033[1;31m(old_text not found — edit will fail)\033[0m\n")
    sys.exit(0)
lines=content.splitlines()
old_lines=o.splitlines()
match_line=0
for i in range(len(lines)):
    if lines[i].rstrip()==old_lines[0].rstrip() if old_lines else True:
        segment="\n".join(lines[i:i+len(old_lines)])
        if segment.rstrip()==o.rstrip():
            match_line=i+1
            break
line_s=("  "+DIM+"·L"+str(match_line)+RST) if match_line else ""
sys.stdout.write("    ✏️   "+pdir_s+BOLD+pbase+RST+line_s+"\n")
diff=list(difflib.unified_diff(o.splitlines(keepends=True),n.splitlines(keepends=True),n=3))
if not diff:
    sys.stdout.write("    "+DIM+"(no change)"+RST+"\n")
for l in diff:
    if l.startswith("+++") or l.startswith("---"):
        continue
    elif l.startswith("@@"):
        m=re.match(r"@@ -(\d+)",l)
        lnum=m.group(1) if m else "?"
        sys.stdout.write("    "+DIM+"╌ L"+lnum+RST+"\n")
    elif l.startswith("+"):
        sys.stdout.write("    "+GRN+l.rstrip()+RST+"\n")
    elif l.startswith("-"):
        sys.stdout.write("    "+RED+l.rstrip()+RST+"\n")
    else:
        sys.stdout.write("    "+DIM+l.rstrip()+RST+"\n")
' 2>/dev/null || echo -e "    \033[0;90m(diff unavailable)\033[0m"
}

# ─── Interactive hunk review ───────────────────────────────────────────────
# Returns 0 if accepted, 1 if rejected. 
# If hunks are split, writes partially accepted content to stdout.
review_hunks() {
  local path="$1"
  local old_file="$2"
  local new_file="$3"
  
  # If not interactive or disabled, accept all
  if [[ "${AGENT_INTERACTIVE_DIFF:-true}" != "true" ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    cat "$new_file"
    return 0
  fi

  # Create an empty file to compare if old_file doesn't exist
  local _temp_old=""
  if [ ! -f "$old_file" ]; then
    _temp_old=$(mktemp)
    old_file="$_temp_old"
  fi

  python3 -c '
import sys, os, difflib, re

path = sys.argv[1]
old_p = sys.argv[2]
new_p = sys.argv[3]

with open(old_p, "r") as f: old_lines = f.readlines()
with open(new_p, "r") as f: new_lines = f.readlines()

diff = list(difflib.unified_diff(old_lines, new_lines, fromfile=path, tofile=path, n=3))
if not diff:
    with open(new_p, "r") as f: sys.stdout.write(f.read())
    sys.exit(0)

def get_hunks(diff):
    hunks = []
    current_hunk = []
    for line in diff:
        if line.startswith("@@"):
            if current_hunk: hunks.append(current_hunk)
            current_hunk = [line]
        elif current_hunk:
            current_hunk.append(line)
    if current_hunk: hunks.append(current_hunk)
    return hunks

hunks = get_hunks(diff)
if not hunks:
    with open(new_p, "r") as f: sys.stdout.write(f.read())
    sys.exit(0)

accepted_hunks = []
GRN, RED, DIM, RST, BOLD = "\033[0;32m", "\033[0;31m", "\033[0;90m", "\033[0m", "\033[1;37m"

sys.stderr.write(f"\n{BOLD}Reviewing changes for {path}:{RST}\n")

apply_all = False
for i, hunk in enumerate(hunks):
    if apply_all:
        accepted_hunks.append(hunk)
        continue

    # Show hunk
    for line in hunk:
        if line.startswith("@@"):
            sys.stderr.write(f"{DIM}{line.strip()}{RST}\n")
        elif line.startswith("+"):
            sys.stderr.write(f"{GRN}{line.rstrip()}{RST}\n")
        elif line.startswith("-"):
            sys.stderr.write(f"{RED}{line.rstrip()}{RST}\n")
        else:
            sys.stderr.write(f"{line.rstrip()}\n")
    
    while True:
        sys.stderr.write(f"{BOLD}Accept hunk {i+1}/{len(hunks)}? [y,n,a,q,?] {RST}")
        sys.stderr.flush()
        # Read from /dev/tty to avoid consuming stdin
        with open("/dev/tty", "r") as tty:
            choice = tty.readline().strip().lower()
        
        if choice == "y":
            accepted_hunks.append(hunk)
            break
        elif choice == "n":
            break
        elif choice == "a":
            accepted_hunks.append(hunk)
            apply_all = True
            break
        elif choice == "q":
            sys.stderr.write("Aborting all changes.\n")
            sys.exit(1)
        elif choice == "?":
            sys.stderr.write("y: accept hunk\nn: reject hunk\na: accept all remaining\nq: quit (reject all)\n")
        else:
            sys.stderr.write("Invalid choice.\n")

if not accepted_hunks:
    with open(old_p, "r") as f: sys.stdout.write(f.read())
    sys.exit(0)

# Re-construct file from accepted hunks using patch logic (simplified)
# We use a temporary patch file and the "patch" command if available, 
# but for zero-deps we can do it in python.
# Simplified approach: If we rejected some hunks, we need to apply only some.
# Better approach: Generate a new patch containing only accepted hunks.

patch_lines = diff[:2] # Header
for hunk in accepted_hunks:
    patch_lines.extend(hunk)

with open("hunk.patch", "w") as f:
    f.writelines(patch_lines)

# Apply patch to old_file and stream to stdout
import subprocess
try:
    # Use patch command for robustness
    subprocess.run(["patch", "-p0", "-o", "-", old_p, "hunk.patch"], stdout=sys.stdout, check=True, stderr=subprocess.DEVNULL)
except:
    # Fallback to applying manually if patch fails or not found (complex but needed for zero-deps)
    # For now, let is assume patch exists or we fail.
    # Actually, lets use a simpler python-based applier for basic hunks.
    sys.stderr.write("Error applying patch. Defaulting to original.\n")
    with open(old_p, "r") as f: sys.stdout.write(f.read())
finally:
    if os.path.exists("hunk.patch"): os.remove("hunk.patch")
' "$path" "$old_file" "$new_file"
  local _ec=$?
  [ -n "$_temp_old" ] && rm -f "$_temp_old"
  return $_ec
}

