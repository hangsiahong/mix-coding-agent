# ─── Wiki solutions writer ────────────────────────────────────────────────────
# Call after a successful task: write_wiki_solution "title" "problem" "fix" "cmd"
write_wiki_solution() {
  local title="$1" problem="$2" fix="$3" cmd="$4"
  local sdir="$WORKDIR/memorybank/solutions"
  mkdir -p "$sdir" 2>/dev/null || return
  local slug; slug=$(printf '%s' "$title" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
  local file="$sdir/${slug}.md"
  if [ ! -f "$file" ]; then
    printf '# Fix: %s
Cause: %s
Fix: %s
Command: `%s`
Date: %s
' \
      "$title" "$problem" "$fix" "$cmd" "$(date '+%Y-%m-%d')" > "$file"
    echo -e "    \033[0;90m↳ wiki: $file\033[0m"
  fi
}

