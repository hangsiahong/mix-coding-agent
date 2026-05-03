# ─── History ─────────────────────────────────────────────────────────────────
HISTORY='[]'
if [ -f "$HIST_FILE" ] && [ -s "$HIST_FILE" ]; then
  _hist_tmp=$(cat "$HIST_FILE")
  if python3 -c 'import json,sys;json.loads(sys.stdin.read())' <<< "$_hist_tmp" 2>/dev/null; then
    HISTORY="$_hist_tmp"
  else
    echo "  Warning: history file corrupted, starting fresh."
    rm -f "$HIST_FILE"
  fi
fi

save_history() {
  if [ -n "${KCONSOLE_API_KEY:-}" ]; then
    printf '%s' "$HISTORY" | sed "s/$KCONSOLE_API_KEY/\[REDACTED_API_KEY\]/g" > "$HIST_FILE"
  else
    printf '%s' "$HISTORY" > "$HIST_FILE"
  fi
}

