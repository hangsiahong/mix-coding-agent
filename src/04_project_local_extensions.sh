# ─── Project-local extensions ────────────────────────────────────────────────
# Load repo-specific tools/overrides, then user-global rc
[ -f "$WORKDIR/.agent/rc.sh" ]    && source "$WORKDIR/.agent/rc.sh"
[ -f "$HOME/.mix/rc.sh" ]  && source "$HOME/.mix/rc.sh"

