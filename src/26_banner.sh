# ─── Sandbox startup detection (must run before banner so 🔒 shows) ─────────
# Parse --sandbox flag
for _arg in "$@"; do
  if [ "$_arg" = "--sandbox" ]; then
    if [ -d "${HOME}/.mix/sandbox-rootfs" ]; then
      SANDBOX_ENABLED=true
    else
      if [ -f "${HOME}/.mix/sandbox-rootfs.tar.gz" ]; then
        _sandbox_unpack_rootfs 2>/dev/null && SANDBOX_ENABLED=true || \
          echo -e "  \033[1;31m✗\033[0m --sandbox: failed to unpack rootfs. Run /sandbox setup."
      else
        echo -e "  \033[1;31m✗\033[0m --sandbox: rootfs not found. Run /sandbox setup first."
      fi
    fi
  fi
done
# Auto-enable from .mix/sandbox marker file
if [ "$SANDBOX_ENABLED" != "true" ] && [ -f "${WORKDIR:-$PWD}/.mix/sandbox" ]; then
  if [ -d "${HOME}/.mix/sandbox-rootfs" ]; then
    SANDBOX_ENABLED=true
  elif [ -f "${HOME}/.mix/sandbox-rootfs.tar.gz" ]; then
    _sandbox_unpack_rootfs 2>/dev/null && SANDBOX_ENABLED=true || \
      echo -e "  \033[1;33m⚠\033[0m .mix/sandbox marker found but failed to unpack rootfs. Run /sandbox setup."
  else
    echo -e "  \033[1;33m⚠\033[0m .mix/sandbox marker found but rootfs not installed. Run /sandbox setup."
  fi
fi

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "  \033[38;5;99m◆\033[0m \033[1mmix\033[0m \033[0;90m· minimal coding agent\033[0m"

# build status line
_provider_label="${PROVIDER:-default}"
_status_line="    \033[0;90mprovider \033[0;33m${_provider_label}\033[0m \033[0;90m• model \033[1;36m${MODEL}\033[0m \033[0;90m• in \033[0m${WORKDIR}"
[ "$AUTO_YES" = "true" ]      && _status_line+=" \033[0;90m•\033[0m \033[1;33m⚡ yolo\033[0m"
[ "$CAVEMAN_MODE" != "off" ]  && _status_line+=" \033[0;90m•\033[0m \033[0;35m🪨 caveman:${CAVEMAN_MODE}\033[0m"
[ "$AGENT_MODE"   != "fast" ] && _status_line+=" \033[0;90m•\033[0m \033[0;36m◎ ${AGENT_MODE}\033[0m"
[ "${SANDBOX_ENABLED:-false}" = "true" ] && _status_line+=" \033[0;90m•\033[0m \033[0;32m🔒 sandbox\033[0m"
[ -n "$ENV_INFO" ]            && _status_line+=" \033[0;90m• [${ENV_INFO}]\033[0m"
echo -e "$_status_line"
if [ -f "$WORKDIR/SPEC.md" ]; then
  echo -e "    \033[0;33m/spec [bug:|amend]  /build [§T.n|--next|--all]  /check [§V|§I|§T|--all]\033[0m"
else
  echo -e "    \033[0;90m/spec <idea>  — start a spec-driven project\033[0m"
fi
echo -e "    \033[0;90mcommands: /flush /refresh /compact /model [id] /models /caveman /mode /yolo /workers /exit\033[0m"
echo -e "    \033[0;90mshortcuts: Tab=complete  Ctrl+E=editor  Ctrl+V=paste  /help=all commands\033[0m"
echo ""

# tmux: rename window + initial status bar
if [ -n "$TMUX" ]; then
  _MIX_SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  tmux rename-window "mix" 2>/dev/null || true
  tmux_update
  echo -e "    \033[0;90msession: ${_MIX_SESSION_NAME}  │  /worker <name> <cmd>  │  /workers\033[0m"
  echo ""
fi

