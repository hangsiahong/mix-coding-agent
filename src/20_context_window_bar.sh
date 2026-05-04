# ─── Context window % bar ─────────────────────────────────────────────────────
ctx_bar() {
  local hist_chars=${#HISTORY}
  local est_tokens=$(( hist_chars / 3 ))
  local pct=$(( est_tokens * 100 / CTX_TOKENS ))
  [ "$pct" -gt 100 ] && pct=100
  local filled=$(( pct * 20 / 100 )) i bar=""
  for ((i=0; i<filled; i++)); do bar+="━"; done
  for ((i=filled; i<20; i++)); do bar+="─"; done
  local color="\033[0;32m"
  [ "$pct" -gt 70 ] && color="\033[0;33m"
  [ "$pct" -gt 90 ] && color="\033[0;31m"
  local ktok=$(( est_tokens / 1000 ))
  local _usage_info=""
  if [ "$_SESSION_API_CALLS" -gt 0 ]; then
    local _total_tok=$(( (_SESSION_PROMPT_TOKENS + _SESSION_COMPLETION_TOKENS) / 1000 ))
    _usage_info="  \033[0;90m│ session: ${_SESSION_API_CALLS} calls, ~${_total_tok}k tokens used\033[0m"
  fi
  printf "  %b%s %3d%%%b  %dk / %dk tokens\033[0m\n" \
    "$color" "$bar" "$pct" "\033[0;90m" "$ktok" "$(( CTX_TOKENS / 1000 ))"
  [ -n "$_usage_info" ] && printf '%b\n' "$_usage_info"
}

