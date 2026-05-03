# ─── Tmux bootstrap ──────────────────────────────────────────────
# Auto-launch or attach a project-scoped tmux session.
# Bypass with: MIX_NO_TMUX=1 mix
if [ -z "${TMUX:-}" ] && [ -t 0 ] && [ "${MIX_NO_TMUX:-}" != "1" ] \
   && command -v tmux >/dev/null 2>&1; then
  _MIX_SESSION="mix-$(basename "$WORKDIR")"
  if tmux has-session -t "$_MIX_SESSION" 2>/dev/null; then
    printf "  \033[0;90m↳ attaching tmux: %s\033[0m\n" "$_MIX_SESSION"
    exec tmux attach-session -t "$_MIX_SESSION"
  else
    exec tmux new-session -s "$_MIX_SESSION" "$0" "$@"
  fi
fi

