#!/usr/bin/env bash
# mix install script
# Usage: curl -fsSL https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master/install.sh | bash

set -e

# Portable readlink -f (macOS has no -f flag)
_rl_f() { python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"; }

REPO="https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master"
SCRIPT_URL="$REPO/mix"
INSTALL_DIR=""
BOLD="\033[1m"; GRN="\033[0;32m"; CYN="\033[0;36m"; YLW="\033[0;33m"; RED="\033[0;31m"; RST="\033[0m"

banner() {
  echo -e ""
  echo -e "${BOLD}  ┌─────────────────────────────────┐${RST}"
  echo -e "${BOLD}  │   mix · minimal coding agent    │${RST}"
  echo -e "${BOLD}  └─────────────────────────────────┘${RST}"
  echo -e ""
}

die() { echo -e "${RED}error: $1${RST}" >&2; exit 1; }
ok()  { echo -e "${GRN}  ✓ $1${RST}"; }
info(){ echo -e "${CYN}  → $1${RST}"; }

# ── Dependency check ──────────────────────────────────────────────────────────
check_deps() {
  local missing=()
  command -v bash   >/dev/null 2>&1 || missing+=("bash")
  command -v curl   >/dev/null 2>&1 || missing+=("curl")
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  if [ ${#missing[@]} -gt 0 ]; then
    die "missing dependencies: ${missing[*]}\nInstall them first, then re-run."
  fi
  ok "dependencies: bash curl python3"
}

# ── Pick install dir ──────────────────────────────────────────────────────────
pick_dir() {
  # prefer ~/bin (no sudo needed), fallback to /usr/local/bin
  if [ -d "$HOME/bin" ]; then
    INSTALL_DIR="$HOME/bin"
  elif echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin"; then
    mkdir -p "$HOME/.local/bin"
    INSTALL_DIR="$HOME/.local/bin"
  elif [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    mkdir -p "$HOME/bin"
    INSTALL_DIR="$HOME/bin"
    # ensure ~/bin is in PATH for this session
    export PATH="$HOME/bin:$PATH"
  fi
  info "install dir: $INSTALL_DIR"
}

# ── Download ──────────────────────────────────────────────────────────────────
download() {
  info "downloading mix..."
  _TMP_BIN=$(mktemp /tmp/mix-install-XXXXXX.bin)
  if ! curl -fsSL "$SCRIPT_URL" -o "$_TMP_BIN"; then
    rm -f "$_TMP_BIN"
    die "download failed. check your internet connection."
  fi
  chmod +x "$_TMP_BIN"
  ok "downloaded"
}

# ── Health gate ───────────────────────────────────────────────────────────────
health_check() {
  info "running self-test..."
  local _out
  _out=$(timeout 5 bash "$_TMP_BIN" --self-test 2>&1)
  if [ $? -ne 0 ] || [ "$_out" != "OK" ]; then
    echo -e "${RED}  ⚠  Self-test failed:${RST}"
    echo "$_out" | head -5 | sed 's/^/    /'
    rm -f "$_TMP_BIN"
    die "downloaded binary failed self-test. try again later."
  fi
  ok "self-test passed"
}

# ── Version ───────────────────────────────────────────────────────────────────
version_install() {
  local _vdir="$HOME/.mix/versions"
  mkdir -p "$_vdir"

  # Timestamped backup
  local _ts
  _ts=$(date +%s)
  local _vbin="$_vdir/${_ts}.bin"
  cp "$_TMP_BIN" "$_vbin"
  ok "versioned → ${_ts}.bin"

  # Update last_good (preserve previous current)
  if [ -L "$_vdir/current" ] && [ -f "$_vdir/current" ]; then
    local _prev
    _prev=$(_rl_f "$_vdir/current")
    if [ -n "$_prev" ] && [ "$_prev" != "$_vbin" ]; then
      ln -sfn "$_prev" "$_vdir/last_good"
    fi
  fi

  # Update current symlink
  ln -sfn "$_vbin" "$_vdir/current"
  ok "current → ${_ts}.bin"

  # Auto-prune: keep last 5
  local _pruned=0
  local _cur_target _lg_target
  _cur_target=$(_rl_f "$_vdir/current")
  _lg_target=$(_rl_f "$_vdir/last_good")
  for _old in $(ls -1t "$_vdir/"*.bin 2>/dev/null | tail -n +6); do
    local _old_real
    _old_real=$(_rl_f "$_old")
    [ "$_old_real" = "$_cur_target" ] && continue
    [ "$_old_real" = "$_lg_target" ] && continue
    rm -f "$_old"
    ((_pruned++)) || true
  done
  [ $_pruned -gt 0 ] && ok "pruned $_pruned old version(s)"

  # Cleanup temp
  rm -f "$_TMP_BIN"
}

# ── Install wrapper ───────────────────────────────────────────────────────────
install_wrapper() {
  local _dest="$INSTALL_DIR/mix"
  cat > "$_dest" << 'WRAPPER'
#!/bin/bash
# mix wrapper — health-checks the current binary, falls back to last_good
# This file is intentionally simple (~30 lines). It should NEVER break.
MIX_DIR="$HOME/.mix/versions"
CRASH_LOG="/tmp/mix-crash.log"
CURRENT="$MIX_DIR/current"
LAST_GOOD="$MIX_DIR/last_good"

# No versions installed yet? Try running from source tree
if [ ! -f "$CURRENT" ]; then
  for _try in "./mix" "$(dirname "$0")/../mix"; do
    [ -f "$_try" ] && exec bash "$_try" "$@"
  done
  echo "mix: no binary found. Run install.sh or build.sh first." >&2
  exit 1
fi

# Quick health check — 3 second timeout
_test_out=$(timeout 3 bash "$CURRENT" --self-test 2>"$CRASH_LOG")
_test_rc=$?
if [ $_test_rc -eq 0 ] && [ "$_test_out" = "OK" ]; then
  exec bash "$CURRENT" "$@"
fi

# Current binary is broken — try last_good in --doctor mode
echo "⚠️  Broken build detected." >&2
if [ -f "$CRASH_LOG" ]; then
  echo "  Last error:" >&2
  head -3 "$CRASH_LOG" | sed 's/^/    /' >&2
fi

if [ -f "$LAST_GOOD" ]; then
  echo "  Booting last_good in --doctor mode..." >&2
  exec bash "$LAST_GOOD" --doctor "$@"
fi

# Catastrophic — no working binary
echo "  No last_good binary available." >&2
echo "  Manual recovery: cd to source dir and run 'bash build.sh'" >&2
exit 1
WRAPPER
  chmod +x "$_dest"
  ok "installed wrapper → $_dest"
}

# ── PATH reminder ─────────────────────────────────────────────────────────────
ensure_path() {
  if ! echo "$PATH" | tr ':' '\n' | grep -qF "$INSTALL_DIR"; then
    echo ""
    echo -e "${YLW}  ⚠  $INSTALL_DIR is not in your PATH.${RST}"
    echo -e "  Add this to your shell profile (~/.bashrc / ~/.zshrc / ~/.config/fish/config.fish):"
    echo ""
    if echo "$SHELL" | grep -q fish; then
      echo -e "      fish_add_path $INSTALL_DIR"
    else
      echo -e "      export PATH=\"$INSTALL_DIR:\$PATH\""
    fi
    echo ""
  fi
}

# ── Directory setup ───────────────────────────────────────────────────────────
setup_directories() {
  local mix_dir="$HOME/.mix"

  # Core directories
  mkdir -p "$mix_dir"
  mkdir -p "$mix_dir/skills"
  mkdir -p "$mix_dir/extensions"
  mkdir -p "$mix_dir/providers"
  ok "directories: $mix_dir/{skills,extensions,providers}"

  # Seed global memory if missing
  if [ ! -f "$mix_dir/memory.md" ]; then
    printf '# Global Memory\n\n' > "$mix_dir/memory.md"
    ok "created: memory.md"
  fi

  # Download starter skill if not already present
  local skill_file="$mix_dir/skills/mix.md"
  if [ ! -f "$skill_file" ]; then
    if curl -fsSL "$REPO/skills/mix.md" -o "$skill_file" 2>/dev/null; then
      ok "installed skill: mix.md"
    fi
  else
    # Update to latest if user allows (non-interactive: skip)
    local _latest=""
    _latest=$(curl -fsSL "$REPO/skills/mix.md" 2>/dev/null) || true
    if [ -n "$_latest" ] && [ "$_latest" != "$(cat "$skill_file")" ]; then
      if [ -t 0 ]; then
        printf "  Update mix.md skill to latest? [Y/n] "
        local _ans=""
        read -r _ans </dev/tty || _ans=""
        if [[ "$_ans" != [nN]* ]]; then
          printf '%s' "$_latest" > "$skill_file"
          ok "updated skill: mix.md"
        fi
      fi
    fi
  fi
}

# ── API key / provider setup ──────────────────────────────────────────────────
setup_key() {
  echo ""
  echo -e "${BOLD}  Provider setup${RST}"
  echo -e "  mix supports two providers:"
  echo -e "    ${CYN}1) KConsole${RST}  — free API key from https://ai.koompi.cloud (default)"
  echo -e "    ${CYN}2) Copilot${RST}   — use your existing GitHub Copilot subscription (no extra key)"
  echo ""

  local _choice=""
  if [ -t 0 ]; then
    printf "  Choose provider [1/2] (default: 1): "
    read -r _choice </dev/tty || _choice=""
    _choice="${_choice// /}"
  fi

  if [ "$_choice" = "2" ]; then
    # Copilot: save default, instruct login
    mkdir -p "$HOME/.mix"
    printf 'PROVIDER=copilot\nMODEL=gpt-4o\nBASE_URL=https://api.githubcopilot.com\n' > "$HOME/.mix/defaults"
    ok "Provider set to: Copilot"
    echo ""
    echo -e "  ${YLW}Next step:${RST} run mix and authenticate:"
    echo -e "      mix"
    echo -e "      /provider copilot login"
    echo -e "      /models"
    echo -e "      /model claude-sonnet-4.5"
  else
    # KConsole: check if already set
    echo -e "  mix uses KConsole AI Gateway (https://ai.koompi.cloud)"
    echo -e "  Get your free key at: ${CYN}https://ai.koompi.cloud${RST}"
    echo ""

    if [ -n "${KCONSOLE_API_KEY:-}" ]; then
      ok "KCONSOLE_API_KEY already set in environment"
      return
    fi

    if [ -t 0 ]; then
      printf "  Paste your API key (or press Enter to skip): "
      read -r _key </dev/tty || _key=""
      _key="${_key#"${_key%%[![:space:]]*}"}"
      _key="${_key%"${_key##*[![:space:]]}"}"

      if [ -n "$_key" ]; then
        local profile=""
        if echo "$SHELL" | grep -q fish; then
          profile="$HOME/.config/fish/config.fish"
          local fish_dir; fish_dir=$(dirname "$profile")
          mkdir -p "$fish_dir"
          printf '\nset -gx KCONSOLE_API_KEY "%s"\n' "$_key" >> "$profile"
        elif [ -f "$HOME/.zshrc" ]; then
          profile="$HOME/.zshrc"
          printf '\nexport KCONSOLE_API_KEY="%s"\n' "$_key" >> "$profile"
        else
          profile="$HOME/.bashrc"
          printf '\nexport KCONSOLE_API_KEY="%s"\n' "$_key" >> "$profile"
        fi
        ok "API key saved to $profile"
        export KCONSOLE_API_KEY="$_key"
      else
        echo -e "  ${YLW}Skipped. Set it later:${RST}"
        echo -e "      export KCONSOLE_API_KEY=your_key"
      fi
    else
      echo -e "  ${YLW}Set your API key before running mix:${RST}"
      echo -e "      export KCONSOLE_API_KEY=your_key"
      echo -e "  ${YLW}Or use Copilot:${RST} run mix then /provider copilot login"
    fi
  fi
}

# ── Quick test ────────────────────────────────────────────────────────────────
quick_test() {
  if command -v mix >/dev/null 2>&1 || [ -x "$INSTALL_DIR/mix" ]; then
    echo ""
    ok "mix is ready"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
banner
check_deps
pick_dir
download
health_check
version_install
install_wrapper
ensure_path
setup_directories
setup_key
quick_test

echo ""
echo -e "${BOLD}  Done. Start with:${RST}"
echo ""
echo -e "      ${CYN}mix${RST}"
echo ""
echo -e "  or from any project dir:"
echo ""
echo -e "      ${CYN}cd my-project && mix${RST}"
echo ""
echo -e "  ${CYN}Customize:${RST}"
echo -e "    ~/.mix/rc.sh         — startup overrides (auto-sourced, trusted)"
echo -e "    ~/.mix/skills/       — /skill <name> to inject into context"
echo -e "    ~/.mix/extensions/   — drop .sh plugins (auto-loaded)"
echo -e "    .mixrc               — per-project config (MODEL, CAVEMAN_MODE, etc)"
echo ""
