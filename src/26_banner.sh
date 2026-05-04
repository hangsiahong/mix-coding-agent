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
echo -e "  \033[38;5;99m◆\033[0m \033[1mmix\033[0m  \033[0;90m·  minimal coding agent\033[0m"
echo ""

# Row 1: model · provider  [git:branch]
_provider_label="${PROVIDER:-default}"
_git_ref=""
[ "$GIT_ENABLED" = true ] && _git_ref=$(git -C "$WORKDIR" branch --show-current 2>/dev/null)
printf "    \033[1;36m%s\033[0m  \033[0;90m·\033[0m  \033[0;33m%s\033[0m" "${MODEL}" "${_provider_label}"
[ -n "$_git_ref" ] && printf "  \033[0;90m[\033[0;36mgit:%s\033[0;90m]\033[0m" "$_git_ref"
echo ""

# Row 2: working directory (~ abbreviated)
_short_wd="${WORKDIR:-$PWD}"
_short_wd="${_short_wd/#$HOME/\~}"
echo -e "    \033[0;90m${_short_wd}\033[0m"

# Row 3: active mode flags — only printed when any are set
_mix_flags=()
[ "$AUTO_YES" = "true" ]                 && _mix_flags+=("\033[1;33m⚡ yolo\033[0m")
[ "$CAVEMAN_MODE" != "off" ]             && _mix_flags+=("\033[0;35m🪨 caveman:${CAVEMAN_MODE}\033[0m")
[ "$AGENT_MODE"   != "fast" ]            && _mix_flags+=("\033[0;36m◎ ${AGENT_MODE}\033[0m")
[ "${SANDBOX_ENABLED:-false}" = "true" ] && _mix_flags+=("\033[0;32m🔒 sandbox\033[0m")
if [ ${#_mix_flags[@]} -gt 0 ]; then
  _mix_flagline=""
  for _mf in "${_mix_flags[@]}"; do
    [ -n "$_mix_flagline" ] && _mix_flagline+="  \033[0;90m·\033[0m  "
    _mix_flagline+="$_mf"
  done
  echo -e "    ${_mix_flagline}"
fi

echo ""

# Spec/build hint (yellow when SPEC.md present, grey otherwise)
if [ -f "$WORKDIR/SPEC.md" ]; then
  echo -e "    \033[0;33m/spec [bug:|amend]  /build [§T.n|--next|--all]  /check [§V|§I|§T|--all]\033[0m"
else
  echo -e "    \033[0;90m/spec <idea>  —  start a spec-driven project\033[0m"
fi

# Single compact hint line
echo -e "    \033[0;90m/help  ·  Tab=complete  ·  Ctrl+E=editor  ·  Ctrl+V=paste\033[0m"
echo ""

# ─── Doctor mode (if booted from wrapper due to broken build) ────────────────
if [ "${_DOCTOR_MODE:-false}" = "true" ]; then
  echo -e "  \033[1;33m⚠ Doctor mode — previous build was broken\033[0m"
  echo -e "  \033[0;90m─────────────────────────────────────────────\033[0m"
  _CRASH_LOG="/tmp/mix-crash.log"
  if [ -f "$_CRASH_LOG" ]; then
    echo -e "  \033[0;31mCrash log:\033[0m"
    sed 's/^/    /' "$_CRASH_LOG" | head -5
  fi
  echo ""
  echo -e "  \033[0;90mRunning from last_good binary. You can:\033[0m"
  echo -e "    \033[0;36m/reload\033[0m     — rebuild from source (if you fixed the issue)"
  echo -e "    \033[0;36mfix the build\033[0m — describe what broke and I'll try to repair"
  echo -e "  \033[0;90m─────────────────────────────────────────────\033[0m"
  echo ""
fi

# tmux: rename window + status bar + session line
if [ -n "$TMUX" ]; then
  _MIX_SESSION_NAME=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  tmux rename-window "mix" 2>/dev/null || true
  tmux_update
  echo -e "    \033[0;90msession: ${_MIX_SESSION_NAME}  │  /worker <name> <cmd>  │  /workers\033[0m"
  echo ""
fi

