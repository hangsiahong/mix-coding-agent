# ─── Proactive Memory ────────────────────────────────────────────────────────
# Analyzes recent history to extract lessons and updates memorybank.

proactive_memory() {
  local input="$1"
  local tools_used="$2"
  
  # Only trigger if tools were used and memorybank exists
  [ "$tools_used" -le 0 ] && return
  [ ! -d "$WORKDIR/memorybank" ] && return
  
  # Check if we should log based on history (e.g., success markers)
  if printf '%s' "$HISTORY" | grep -q '"role": "tool", "content": "Edited'; then
    local slug; slug=$(printf '%s' "$input" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
    local sfile="$WORKDIR/memorybank/solutions/${slug}.md"
    
    # If solution file already exists, maybe append? For now, only create if new.
    if [ ! -f "$sfile" ]; then
      # Use a small reflection turn if possible, but for now just extract
      local _summary; _summary=$(printf '%s' "$HISTORY" | python3 -c '
import json,sys
h=json.load(sys.stdin)
content = ""
for m in reversed(h):
    if m.get("role")=="assistant" and m.get("content"):
        content = m["content"][:1000]
        break
print(content)
' 2>/dev/null || true)

      mkdir -p "$WORKDIR/memorybank/solutions" 2>/dev/null
      {
        echo "# Task: $input"
        echo "Date: $(date '+%Y-%m-%d')"
        echo ""
        echo "## Result"
        echo "$_summary"
        echo ""
        echo "## Files Modified"
        printf '%s' "$HISTORY" | python3 -c '
import json,sys,re
h=json.load(sys.stdin)
files = set()
for m in h:
    if m.get("role")=="tool" and m.get("name")=="edit_file":
        res = m.get("content","")
        match = re.search(r"Edited ([^ ]+)", res)
        if match: files.add(match.group(1))
for f in sorted(files): print(f"- {f}")
' 2>/dev/null
      } > "$sfile"
      
      # Update log.md
      printf '## [%s] ingest | %s\n' "$(date '+%Y-%m-%d')" "$input" >> "$WORKDIR/memorybank/log.md"
      # Update index.md if it exists
      if [ -f "$WORKDIR/memorybank/index.md" ]; then
         printf '- [%s](solutions/%s.md): %s\n' "$input" "$slug" "$input" >> "$WORKDIR/memorybank/index.md"
      fi
      
      echo -e "  \033[0;90m$I_OK Proactive memory logged to solutions/${slug}.md\033[0m"
    fi
  fi
}
