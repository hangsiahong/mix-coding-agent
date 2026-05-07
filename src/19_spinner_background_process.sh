# ─── Spinner (background process) ────────────────────────────────────────────
_SPIN_PID=""
_SPIN_FORTUNE_IDX=0

# Fun facts / tips shown while waiting. Rotates each spinner invocation.
_SPIN_FORTUNES=(
  "type /resume to restore your last session"
  "edit_file uses 4 strategies: exact, fuzzy, indent, anchor"
  "mix auto-compacts history when it exceeds 60 msgs"
  "set EDITOR=vim to edit prompts in your editor"
  "/cache shows what files are cached in context"
  "/stats tracks your session token usage"
  "repo map auto-rebuilds every 10 minutes"
  "parallel read_file calls run simultaneously"
  "/afk <task> lets mix work while you grab coffee"
  "/undo reverts the last edit via git"
  "skills load from ~/.mix/skills/ — try /skills"
  "/ext create <name> scaffolds a new extension"
  "file cache survives history compaction"
  "mix is a single bash file — no node_modules"
  "caveman mode: less words, more code"
  "/sandbox on runs bash in an Alpine chroot"
  "/compact manually triggers history compression"
  "Ctrl+C cancels the current turn, not the session"
  "providers are pluggable — see ~/.mix/providers/"
  "auto-verify runs lint+typecheck after every edit"
)

_spin_fortune() {
  local _len=${#_SPIN_FORTUNES[@]}
  [ "$_len" -eq 0 ] && return
  local _idx=$(( _SPIN_FORTUNE_IDX % _len ))
  _SPIN_FORTUNE_IDX=$(( _idx + 1 ))
  printf '%s' "${_SPIN_FORTUNES[$_idx]}"
}

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

  # Pick a fortune to show alongside the label
  local fortune=""
  fortune=$(_spin_fortune)

  (while :; do
    for f in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
      if [ "$INTERACTIVE" = false ]; then
        printf "\r\033[K    \033[%s%s\033[0m \033[0;90m%s...\033[0m" "$color" "$f" "$label" >&2
      else
        printf "\r\033[K    \033[%s%s\033[0m \033[0;90m%s · %s\033[0m" "$color" "$f" "$label" "$fortune" >/dev/tty 2>/dev/null
      fi
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

