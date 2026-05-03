#!/usr/bin/env bash
# mix install script
# Usage: curl -fsSL https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master/install.sh | bash

set -e

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
  local dest="$INSTALL_DIR/mix"
  if ! curl -fsSL "$SCRIPT_URL" -o "$dest"; then
    die "download failed. check your internet connection."
  fi
  chmod +x "$dest"
  ok "installed: $dest"
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
  local skills_dir="$mix_dir/skills"
  if [ ! -d "$skills_dir" ]; then
    mkdir -p "$skills_dir"
    info "created skill directory: $skills_dir"
  else
    ok "skill directory exists: $skills_dir"
  fi
}

# ── API key setup ─────────────────────────────────────────────────────────────
setup_key() {
  echo ""
  echo -e "${BOLD}  API key setup${RST}"
  echo -e "  mix uses KConsole AI Gateway (https://ai.koompi.cloud)"
  echo -e "  Get your free key at: ${CYN}https://ai.koompi.cloud${RST}"
  echo ""

  # Check if already set
  if [ -n "${KCONSOLE_API_KEY:-}" ]; then
    ok "KCONSOLE_API_KEY already set in environment"
    return
  fi

  # Interactive only
  if [ -t 0 ]; then
    printf "  Paste your API key (or press Enter to skip): "
    read -r _key </dev/tty || _key=""
    _key="${_key#"${_key%%[![:space:]]*}"}"  # trim
    _key="${_key%"${_key##*[![:space:]]}"}"

    if [ -n "$_key" ]; then
      # detect shell profile
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
    # Non-interactive (piped)
    echo -e "  ${YLW}Set your API key before running mix:${RST}"
    echo -e "      export KCONSOLE_API_KEY=your_key"
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
