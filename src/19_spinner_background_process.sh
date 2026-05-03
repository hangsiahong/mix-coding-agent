# ─── Spinner (background process) ────────────────────────────────────────────
_SPIN_PID=""
start_spinner() {
  local label="${1:-thinking}"
  (while :; do
    for f in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
      [ "$INTERACTIVE" = false ] && printf "\r\033[K    \033[38;5;99m%s\033[0m \033[0;90m%s...\033[0m" "$f" "$label" >&2 || printf "\r\033[K    \033[38;5;99m%s\033[0m \033[0;90m%s...\033[0m" "$f" "$label" >/dev/tty 2>/dev/null
      sleep 0.08 2>/dev/null || sleep 1
    done
  done) &
  _SPIN_PID=$!
}
stop_spinner() {
  [ -n "$_SPIN_PID" ] && kill "$_SPIN_PID" 2>/dev/null && wait "$_SPIN_PID" 2>/dev/null
  _SPIN_PID=""
  [ "$INTERACTIVE" = false ] && printf "\r\033[K" >&2 || printf "\r\033[K" >/dev/tty 2>/dev/null
}

