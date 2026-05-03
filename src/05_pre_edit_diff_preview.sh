# ─── Pre-edit diff preview ──────────────────────────────────────────────────
show_edit_diff() {
  local targs="$1"
  printf '%s' "$targs" | python3 -c '
import json,sys,os,difflib
d=json.load(sys.stdin)
p,o,n=d.get("path","?"),d.get("old_text",""),d.get("new_text","")
GRN,RED,DIM,RST="\033[0;32m","\033[0;31m","\033[0;90m","\033[0m"
if not os.path.exists(p):
    sys.stdout.write(DIM+"    (new file)\n"+RST)
    for l in n.splitlines(): sys.stdout.write("    "+GRN+"+ "+l+RST+"\n")
    sys.exit(0)
content=open(p).read()
if o not in content:
    sys.stdout.write("    \033[1;31m(old_text not found — edit will fail)\033[0m\n")
    sys.exit(0)
diff=list(difflib.unified_diff(o.splitlines(keepends=True),n.splitlines(keepends=True),fromfile="before",tofile="after",n=2))
if not diff:
    sys.stdout.write(DIM+"    (no change)\n"+RST)
for l in diff:
    if l.startswith("+") and not l.startswith("+++"):
        sys.stdout.write("    "+GRN+l.rstrip()+RST+"\n")
    elif l.startswith("-") and not l.startswith("---"):
        sys.stdout.write("    "+RED+l.rstrip()+RST+"\n")
    else:
        sys.stdout.write("    "+DIM+l.rstrip()+RST+"\n")
' 2>/dev/null || echo -e "    \033[0;90m(diff unavailable)\033[0m"
}

