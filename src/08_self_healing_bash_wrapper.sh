# ─── Self-healing bash wrapper ───────────────────────────────────────────────
run_with_heal() {
  local cmd="$1" out rc
  out=$(bash -c "$cmd" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    # Permission denied → retry with sudo
    if printf '%s' "$out" | grep -qiE 'permission denied|EACCES'; then
      echo -e "    \033[0;90m↻ permission denied\033[0m"
      local _sudo_ans=""
      echo -e "    \033[1;33mCommand:\033[0m \033[0;90msudo bash -c \"$cmd\"\033[0m"
      printf '    \033[1;33mConfirm sudo? [y/N] \033[0m'
      read -r _sudo_ans < /dev/tty 2>/dev/null || _sudo_ans="n"
      if [[ "$_sudo_ans" == [yY]* ]]; then
        out=$(sudo bash -c "$cmd" 2>&1); rc=$?
      fi
    # command not found → only retry for npm-style packages (contain - or @, no path separators)
    elif printf '%s' "$out" | grep -qiE 'command not found|: No such file or directory'; then
      local _bin; _bin=$(printf '%s' "$cmd" | awk '{print $1}')
      if command -v "node_modules/.bin/$_bin" >/dev/null 2>&1; then
        echo -e "    \033[0;90m↻ not found — retrying via node_modules/.bin\033[0m"
        out=$(bash -c "node_modules/.bin/$cmd" 2>&1); rc=$?
      elif command -v npx >/dev/null 2>&1 \
        && printf '%s' "$_bin" | grep -qE '^[@a-z]' \
        && printf '%s' "$_bin" | grep -qE '[-@]' \
        && ! printf '%s' "$_bin" | grep -qE '[/_]'; then
        echo -e "    \033[0;90m↻ not found — retrying via npx\033[0m"
        out=$(bash -c "npx $cmd" 2>&1); rc=$?
      fi
    fi
    [ $rc -ne 0 ] && out="[FAILED exit=$rc]
$out"
  fi

  # Context bloat control: truncate output if it exceeds 200 lines
  local total_lines
  total_lines=$(printf '%s\n' "$out" | wc -l)
  if [ "$total_lines" -gt 200 ]; then
    out="$(printf '%s\n' "$out" | head -n 100)
... ($((total_lines - 200)) lines truncated by mix to prevent context bloat) ...
$(printf '%s\n' "$out" | tail -n 100)"
  fi

  printf '%s' "$out"
}

