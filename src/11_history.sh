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

# ─── Universal history sanitizer ─────────────────────────────────────────────
# Call before every API request. Handles:
#   Google: strips tool_calls missing thought_signature (converts to text)
#   Non-Google: strips thought_signature from tool_calls (Google-specific field)
# This allows seamless provider switching without /flush.
_apply_provider_history_filter() {
  local hist="$1"

  # Step 1: Provider-specific filter (Google strips unsigned tool_calls)
  if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_filter_history" >/dev/null 2>&1; then
    hist=$(printf '%s' "$hist" | ${PROVIDER}_filter_history 2>/dev/null) || true
    [ -z "$hist" ] && hist="$1"
  fi

  # Step 2: When NOT on Google, strip thought_signature from all tool_calls
  # (prevents sending Google-specific fields to Copilot/koompi/etc.)
  if [ "$PROVIDER" != "google" ]; then
    hist=$(printf '%s' "$hist" | python3 -c '
import json,sys
h=json.load(sys.stdin)
for msg in h:
    if msg.get("tool_calls"):
        for tc in msg["tool_calls"]:
            tc.pop("thought_signature", None)
print(json.dumps(h))
' 2>/dev/null) || true
    [ -z "$hist" ] && hist="$1"
  fi

  printf '%s' "$hist"
}

