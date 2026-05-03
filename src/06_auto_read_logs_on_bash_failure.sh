# ─── Auto-read logs on bash failure ─────────────────────────────────────────
auto_read_logs() {
  local err="$1" log_ctx=""
  # Extract file paths ending in .log/.err/.out mentioned in error
  local paths
  paths=$(printf '%s' "$err" | grep -oE '(/[^ :"]+\.(log|err|out)|[^ :"]+\.log)' | sort -u | head -3)
  while IFS= read -r lp; do
    [ -z "$lp" ] && continue
    if [ -f "$lp" ]; then
      log_ctx+="[auto-log: $lp (last 20 lines)]\n$(tail -20 "$lp" 2>/dev/null)\n"
    fi
  done <<< "$paths"
  printf '%s' "$log_ctx"
}

