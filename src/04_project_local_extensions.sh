# ─── Project-local extensions ────────────────────────────────────────────────
# Load repo-specific tools/overrides, then user-global rc
if [ -f "$WORKDIR/.agent/rc.sh" ]; then
  echo -e "  \033[0;33m⚠  Sourcing project rc: $WORKDIR/.agent/rc.sh\033[0m"
  source "$WORKDIR/.agent/rc.sh"
fi
if [ -f "$HOME/.mix/rc.sh" ]; then
  source "$HOME/.mix/rc.sh"
fi

