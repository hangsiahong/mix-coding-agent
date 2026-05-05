# ─── Nerd Font Icons ─────────────────────────────────────────────────────────
# Centralized icon definitions. Falls back to emoji when Nerd Font not detected.
# All TUI output should use these variables instead of hardcoded emoji.

# Detect Nerd Font support (check common NF-capable terminals + explicit opt-in)
_nf_supported() {
  # User can force via env var
  [ "${MIX_NERD_FONTS:-}" = "1" ] && return 0
  [ "${MIX_NERD_FONTS:-}" = "0" ] && return 1
  # Check known Nerd Font terminals
  case "${TERM_PROGRAM:-}" in
    iTerm.app|WezTerm|Alacritty|kitty|ghostty) return 0 ;;
  esac
  # Check TERM for tmux/screen (often NF-capable inside)
  case "${TERM:-}" in
    xterm-256color|screen-256color|tmux-256color) return 0 ;;
  esac
  # Check if common NF glyph renders (heuristic: most terminals won't crash)
  return 1
}

if _nf_supported; then
  # Nerd Font glyphs — crisp, monospace-aligned, no width ambiguity
  I_TOOL="󰚩"     # nf-md-tools (was ⚡)
  I_BASH=""      # nf-cod-terminal_bash
  I_WRITE=""     # nf-oct-diff_added (create_file)
  I_EDIT=""      # nf-fa-pencil_alt (edit_file)
  I_FIND="󰈞"     # nf-md-magnify (search_files)
  I_READ=""      # nf-fa-file_text (read_file)
  I_DIR=""       # nf-fa-folder (list_files)
  I_MEMORY="󰍛"   # nf-md-brain (memory)
  I_PLAN="󰍉"     # nf-md-clipboard_text (planning)
  I_VERIFY="󰃰"   # nf-md-check_decagram (verify)
  I_BLOCKED="󰀨"  # nf-md-cancel (was ⛔)
  I_WARN="󰀪"     # nf-md-alert (was ⚠)
  I_RISK_MED="󰀦" # nf-md-shield_half_full (was ◈)
  I_FAIL="󰅙"     # nf-md-close_circle (was ✗)
  I_OK="󰄬"       # nf-md-check (was ✓)
  I_RETRY="󰑐"    # nf-md-restart (was ↻)
  I_ROCK="󰇧"     # nf-md-rock (was 🪨 — caveman)
  I_LOCK="󰌋"     # nf-md-lock (was 🔒 — sandbox)
  I_DIAMOND="󰄐"  # nf-md-diamond (was ◆)
  I_MODE="󰀘"     # nf-md-tune (was ◎)
  I_ARROW_R="󰁔"  # nf-md-chevron_right (sub-indicator)
  I_RETURN="󰌶"   # nf-md-keyboard_return (was ↳)
  I_BRANCH="󰊢"   # nf-md-source_branch (git)
  I_COMMIT="󰜘"   # nf-md-source_commit (git commit)
  I_DIFF="╌"      # keep as-is (Unicode box drawing, not emoji)
  I_YOLO="󰀨"     # nf-md-flash (was ⚡ yolo flag)
  # Battery icons — indexed by 0-10 (pct/10), used by ctx_bar
  I_BAT_0="󰁺"    # 0%
  I_BAT_1="󰁻"    # 10%
  I_BAT_2="󰁼"    # 20%
  I_BAT_3="󰁽"    # 30%
  I_BAT_4="󰁽"    # 40%
  I_BAT_5="󰁾"    # 50%
  I_BAT_6="󰁿"    # 60%
  I_BAT_7="󰂀"    # 70%
  I_BAT_8="󰂁"    # 80%
  I_BAT_9="󰂂"    # 90%
  I_BAT_10="󰁹"   # 100%
else
  # Emoji fallback — works everywhere
  I_TOOL="⚡"
  I_BASH="⚡"
  I_WRITE="📝"
  I_EDIT="✏️"
  I_FIND="🔍"
  I_READ="📄"
  I_DIR="📁"
  I_MEMORY="🧠"
  I_PLAN="📋"
  I_VERIFY="🔍"
  I_BLOCKED="⛔"
  I_WARN="⚠"
  I_RISK_MED="◈"
  I_FAIL="✗"
  I_OK="✓"
  I_RETRY="↻"
  I_ROCK="🪨"
  I_LOCK="🔒"
  I_DIAMOND="◆"
  I_MODE="◎"
  I_ARROW_R="⤷"
  I_RETURN="↳"
  I_BRANCH="⑂"
  I_COMMIT="↳"
  I_DIFF="╌"
  I_YOLO="⚡"
fi
