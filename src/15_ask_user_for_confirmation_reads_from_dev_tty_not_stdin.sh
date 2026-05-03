# ─── Ask user for confirmation (reads from /dev/tty, not stdin) ─────────────
confirm() {
  local prompt="$1"
  if [ "$AUTO_YES" = "true" ] || [ "$INTERACTIVE" = false ]; then return 0; fi
  local answer
  read -r -p "$prompt" answer < /dev/tty || true
  case "$answer" in
    n*|N*) return 1 ;;
    *) return 0 ;;
  esac
}

