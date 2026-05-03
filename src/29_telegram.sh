# ─── Telegram Integration ─────────────────────────────────────────────────────
_TELEGRAM_CONFIG_FILE="${HOME}/.mix/telegram"

telegram_is_configured() {
  [ -f "$_TELEGRAM_CONFIG_FILE" ] || return 1
  grep -q '^BOT_TOKEN=' "$_TELEGRAM_CONFIG_FILE" 2>/dev/null || return 1
  grep -q '^CHAT_ID=' "$_TELEGRAM_CONFIG_FILE" 2>/dev/null || return 1
}

telegram_setup() {
  printf '\n'
  printf '  \033[1;37m─── Telegram AFK Setup ───\033[0m\n'
  printf '\n'
  printf '  1. Open Telegram → message \033[1m@BotFather\033[0m → /newbot → follow prompts\n'
  printf '  2. Copy the bot token (looks like: 1234567890:ABCdef...)\n'
  printf '\n'
  printf '  Paste bot token: '
  local token
  read -r token < /dev/tty
  token="${token// /}"
  [ -z "$token" ] && { printf '  Aborted.\n'; return 1; }

  printf '  Verifying...'
  local resp ok bot_name
  resp=$(curl -s --max-time 10 "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)
  ok=$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print("ok" if d.get("ok") else "fail")' 2>/dev/null)
  if [ "$ok" != "ok" ]; then
    printf '\r  \033[1;31m✗ Invalid token. Check and try again.\033[0m\n'
    return 1
  fi
  bot_name=$(printf '%s' "$resp" | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["username"])' 2>/dev/null)
  printf '\r  \033[38;5;82m✓ Bot verified: @%s\033[0m\n' "$bot_name"
  printf '\n'
  printf '  3. Open Telegram → find \033[1m@%s\033[0m → send any message\n' "$bot_name"
  printf '     Press Enter when done: '
  read -r _ < /dev/tty

  local updates chat_id
  updates=$(curl -s --max-time 10 "https://api.telegram.org/bot${token}/getUpdates" 2>/dev/null)
  chat_id=$(printf '%s' "$updates" | python3 -c '
import json,sys
data=json.load(sys.stdin)
for u in reversed(data.get("result",[])):
    cid=u.get("message",{}).get("chat",{}).get("id","")
    if cid: print(cid); break
' 2>/dev/null)

  if [ -z "$chat_id" ]; then
    printf '  \033[1;31m✗ No message found. Send a message to @%s first, then re-run /afk setup.\033[0m\n' "$bot_name"
    return 1
  fi

  mkdir -p "${HOME}/.mix"
  printf 'BOT_TOKEN=%s\nCHAT_ID=%s\n' "$token" "$chat_id" > "$_TELEGRAM_CONFIG_FILE"
  chmod 600 "$_TELEGRAM_CONFIG_FILE"
  printf '  \033[38;5;82m✓ Saved to %s\033[0m (chat_id: %s)\n' "$_TELEGRAM_CONFIG_FILE" "$chat_id"

  # Send confirmation message
  local payload
  payload=$(python3 -c "import json; print(json.dumps({'chat_id':'${chat_id}','text':'✅ mix AFK connected!\n\nYou will receive plan approvals here when you run /afk.'}))")
  curl -s --max-time 10 -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -H "Content-Type: application/json" -d "$payload" > /dev/null
  printf '  Test message sent to Telegram.\n'
  printf '\n'
  printf '  \033[38;5;82m✓ Setup complete! Run /afk anytime.\033[0m\n'
}
