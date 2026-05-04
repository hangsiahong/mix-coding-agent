# ─── Spinner (background process) ────────────────────────────────────────────
_SPIN_PID=""
start_spinner() {
  local label="${1:-thinking}"
  local color="38;5;99m" # default purple
  if [[ "$ACTIVE_SKILLS" == *"swe-precision"* ]]; then color="38;5;33m" # blue
  elif [[ "$ACTIVE_SKILLS" == *"bug-hunter"* ]]; then color="38;5;196m" # red
  elif [[ "$ACTIVE_SKILLS" == *"security-hardener"* ]]; then color="38;5;208m" # orange
  elif [[ "$ACTIVE_SKILLS" == *"architect-evaluator"* ]]; then color="38;5;51m" # cyan
  elif [[ "$ACTIVE_SKILLS" == *"minimalist-refactor"* ]]; then color="38;5;82m" # green
  # State-based colors: retry → orange, error recovery → red
  elif [[ "$label" == *"retry"* ]]; then color="38;5;208m" # orange
  elif [[ "$label" == *"error"* ]] || [[ "$label" == *"recovery"* ]]; then color="38;5;196m" # red
  fi

  (while :; do
    for f in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
      [ "$INTERACTIVE" = false ] && printf "\r\033[K    \033[%s%s\033[0m \033[0;90m%s...\033[0m" "$color" "$f" "$label" >&2 || printf "\r\033[K    \033[%s%s\033[0m \033[0;90m%s...\033[0m" "$color" "$f" "$label" >/dev/tty 2>/dev/null
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

