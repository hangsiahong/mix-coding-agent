# ─── Self-healing bash wrapper ───────────────────────────────────────────────
run_with_heal() {
  local cmd="$1" out rc
  out=$(eval "$cmd" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    # Permission denied → retry with sudo
    if printf '%s' "$out" | grep -qiE 'permission denied|EACCES'; then
      echo -e "    \033[0;90m↻ permission denied\033[0m"
      local _sudo_ans=""
      printf '    \033[1;33mRetry with sudo? [y/N] \033[0m'
      read -r _sudo_ans < /dev/tty 2>/dev/null || _sudo_ans="n"
      if [[ "$_sudo_ans" == [yY]* ]]; then
        out=$(sudo bash -c "$cmd" 2>&1); rc=$?
      fi
    # npm/node not found → try npx or node prefix
    elif printf '%s' "$out" | grep -qiE 'command not found|: No such file or directory'; then
      local _bin; _bin=$(printf '%s' "$cmd" | awk '{print $1}')
      if command -v "node_modules/.bin/$_bin" >/dev/null 2>&1; then
        echo -e "    \033[0;90m↻ not found — retrying via node_modules/.bin\033[0m"
        out=$(eval "node_modules/.bin/$cmd" 2>&1); rc=$?
      elif command -v npx >/dev/null 2>&1 && printf '%s' "$cmd" | grep -qE '^[a-z]'; then
        echo -e "    \033[0;90m↻ not found — retrying via npx\033[0m"
        out=$(eval "npx $cmd" 2>&1); rc=$?
      fi
    fi
    [ $rc -ne 0 ] && out="[FAILED exit=$rc]
$out"
  fi
  printf '%s' "$out"
}

