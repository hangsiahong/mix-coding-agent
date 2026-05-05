# ─── Context window % bar ─────────────────────────────────────────────────────
_fmt_tok() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    printf '%dM' $(( n / 1000000 ))
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' $(( n / 1000 ))
  else
    printf '%d' "$n"
  fi
}

ctx_bar() {
  local hist_chars=${#HISTORY}
  local sys_chars tools_chars
  sys_chars=$(build_system_prompt | wc -c) || sys_chars=0
  tools_chars=${#TOOLS_JSON}
  
  local total_chars=$(( hist_chars + sys_chars + tools_chars ))
  local est_tokens=$(( total_chars / 3 ))
  local pct=$(( est_tokens * 100 / CTX_TOKENS ))
  [ "$pct" -gt 100 ] && pct=100
  local color="\033[0;32m"
  [ "$pct" -gt 70 ] && color="\033[0;33m"
  [ "$pct" -gt 90 ] && color="\033[0;31m"
  local ktok=$(( est_tokens / 1000 ))
  # Battery icon: index 0-10
  local bat_idx=$(( pct / 10 ))
  [ "$bat_idx" -gt 10 ] && bat_idx=10
  local bat_icon
  eval "bat_icon=\${I_BAT_${bat_idx}:-}"
  printf "  %b%s %d%%%b  %dk / %dk tokens\033[0m\n" \
    "$color" "$bat_icon" "$pct" "\033[0;90m" "$ktok" "$(( CTX_TOKENS / 1000 ))"
  if [ "${_SESSION_API_CALLS:-0}" -gt 0 ]; then
    local _total_tok=$(( _SESSION_PROMPT_TOKENS + _SESSION_COMPLETION_TOKENS ))
    local _total_str; _total_str=$(_fmt_tok $_total_tok)
    local _cache_str=""
    if [ "${_SESSION_CACHE_TOKENS:-0}" -gt 0 ] && [ "${_SESSION_PROMPT_TOKENS:-0}" -gt 0 ]; then
      local _cache_pct=$(( _SESSION_CACHE_TOKENS * 100 / _SESSION_PROMPT_TOKENS ))
      _cache_str=" · \033[38;5;183m${_cache_pct}% cached\033[0m"
    fi
    printf '  \033[38;5;183m│ session: %s calls, ~%s tokens used%b\033[0m\n' \
      "${_SESSION_API_CALLS}" "$_total_str" "$_cache_str"
  fi
  return 0
}

