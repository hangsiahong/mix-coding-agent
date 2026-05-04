# ─── Project-local extensions ────────────────────────────────────────────────
# Only source from ~/.mix/rc.sh — trusted user-controlled location.
# Project-local .agent/rc.sh is NOT auto-sourced (untrusted working directory).
if [ -f "$HOME/.mix/rc.sh" ]; then
  source "$HOME/.mix/rc.sh"
fi

