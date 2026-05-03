# ─── Tmux status updater ──────────────────────────────────────────────────────
tmux_update() {
  [ -z "$TMUX" ] && return
  local hist_chars=${#HISTORY}
  local est_tokens=$(( hist_chars / 3 ))
  local pct=$(( est_tokens * 100 / CTX_TOKENS ))
  [ "$pct" -gt 100 ] && pct=100
  local ctx_color="#[fg=green]"
  [ "$pct" -gt 70 ] && ctx_color="#[fg=yellow]"
  [ "$pct" -gt 90 ] && ctx_color="#[fg=red]"
  local branch_str=""
  [ "$GIT_ENABLED" = true ] && \
    branch_str=" #[fg=white]|#[fg=cyan]$(git -C "$WORKDIR" branch --show-current 2>/dev/null)"
  local mode_str=""
  [ "$AGENT_MODE" != "fast" ] && mode_str=" #[fg=white]|#[fg=magenta]${AGENT_MODE}"
  tmux set-option -gq status-right-length 100 2>/dev/null
  tmux set-option -gq status-right \
    " #[fg=white,bold]mix#[nobold] #[fg=cyan]${MODEL}${branch_str}${mode_str} #[fg=white]| ctx ${ctx_color}${pct}%#[fg=white] #[default]" \
    2>/dev/null || true
}


