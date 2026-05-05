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
    sys.stdout.write("    "+I_WRITE+"  "+pdir_s+BOLD+pbase+RST+"  "+DIM+"(new file)"+RST+"\n")
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