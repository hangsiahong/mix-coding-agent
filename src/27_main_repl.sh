if [ -t 0 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# Trap SIGINT (Ctrl+C) to cancel current turn and return to prompt instead of exiting
trap 'echo -e "\n  \033[1;31m(Turn Cancelled)\033[0m"' SIGINT
# Cleanup trap for crashes and exits (R1, R2)
trap '_ext_hook on_shutdown 2>/dev/null; session_save 2>/dev/null; stop_spinner 2>/dev/null; rm -f /tmp/mix-* 2>/dev/null; exit' EXIT TERM HUP

# ─── Autocomplete ─────────────────────────────────────────────

if [ "$INTERACTIVE" = true ]; then
  _TAB_IDX=0
  _TAB_LAST_WORD=""
  _TAB_LAST_PRE=""
  _TAB_STATE_FILE=$(mktemp -t mix-tab-XXXXXX 2>/dev/null) || _TAB_STATE_FILE="/tmp/mix-tab-$$"
  printf '%s\n' "0" "" "" "" > "$_TAB_STATE_FILE"

  _mix_bind_tab() {
    local cur="${READLINE_LINE:0:$READLINE_POINT}"
    local word="${cur##* }"
    local pre="${cur:0:$((READLINE_POINT - ${#word}))}"
    local matches=()

    # Tab cycle state — 4 lines: idx | original_query | last_filled | pre
    # Stored in file because bind -x may run in subshell (globals unreliable)
    local _tidx=0 _tquery="" _tcand="" _tpre=""
    if [ -f "$_TAB_STATE_FILE" ]; then
      { IFS= read -r _tidx; IFS= read -r _tquery; IFS= read -r _tcand; IFS= read -r _tpre; } < "$_TAB_STATE_FILE"
    fi
    _tidx="${_tidx:-0}"

    # Determine if we're continuing a cycle or starting fresh.
    # Continuing: the current readline word equals the last filled candidate,
    # and pre hasn't changed. This means user just pressed Tab again without typing.
    local match_word="$word"
    if [[ "$_tcand" == "$word" && "$_tpre" == "$pre" && -n "$_tquery" ]]; then
      match_word="$_tquery"   # rebuild matches against the original query
    else
      # User typed something new — reset cycle state
      _tidx=0; _tquery="$word"; _tcand=""; _tpre="$pre"
      match_word="$word"
    fi

    if [[ "$match_word" == /* ]]; then
        for c in "/flush" "/undo" "/stash" "/stats" "/refresh" "/resume" "/cache" "/verify" "/model" "/provider" "/history" "/caveman" "/mode" "/yolo" "/config" "/ext" "/workers" "/worker" "/subagent" "/skill" "/skills" "/sandbox" "/sandbox install" "/help" "/exit" "/spec" "/build" "/check" "/test"; do
        [[ "$c" == "$match_word"* ]] && matches+=("$c")
      done
    elif [[ "$pre" == "/skill "* ]]; then
      local sfiles=()
      if [ -d ".mix/skills" ]; then
        for f in .mix/skills/*.md; do [ -f "$f" ] && sfiles+=("$(basename "$f" .md)"); done
      fi
      if [ -d "$HOME/.mix/skills" ]; then
        for f in "$HOME/.mix/skills/"*.md; do [ -f "$f" ] && sfiles+=("$(basename "$f" .md)"); done
      fi
      sfiles+=("clear")
      for s in "${sfiles[@]}"; do
        [[ "$s" == "$match_word"* ]] && matches+=("$s")
      done
    elif [[ "$pre" == "/provider "* ]]; then
      local _pnames; _pnames=$(_list_providers 2>/dev/null)
      _pnames+=" default"
      while IFS= read -r _pn; do
        [ -n "$_pn" ] && [[ "$_pn" == "$match_word"* ]] && matches+=("$_pn")
      done <<< "$_pnames"
    elif [[ "$pre" == "/ext "* ]]; then
      local _ext_words="load unload create reload list"
      for _ew in $_ext_words; do
        [[ "$_ew" == "$match_word"* ]] && matches+=("$_ew")
      done
    elif [[ "$pre" == "/ext load "* ]] || [[ "$pre" == "/ext unload "* ]]; then
      local _enames=""
      for f in ~/.mix/extensions/*.sh .mix/extensions/*.sh; do
        [ -f "$f" ] && _enames+="$(basename "$f" .sh) "
      done
      for _en in $_enames; do
        [[ "$_en" == "$match_word"* ]] && matches+=("$_en")
      done
    elif [[ "$pre" == "/caveman "* ]]; then
      for _cm in off lite full ultra; do
        [[ "$_cm" == "$match_word"* ]] && matches+=("$_cm")
      done
    elif [[ "$pre" == "/mode "* ]]; then
      for _mm in fast deep plan; do
        [[ "$_mm" == "$match_word"* ]] && matches+=("$_mm")
      done
    elif [[ "$pre" == "/verify "* ]]; then
      for _vm in on off; do
        [[ "$_vm" == "$match_word"* ]] && matches+=("$_vm")
      done
    elif [[ "$match_word" == @* ]]; then
      local q="${match_word#@}"

      # Special context shortcuts — always offered when query matches
      for _ctx in "git:diff" "git:log" "git:status" "memory"; do
        [[ "$_ctx" == "$q"* ]] && matches+=("@$_ctx")
      done

      # If the query itself starts with a dot, allow matching dotfiles. Otherwise hide them.
      local dotfile_filter
      if [[ "$q" == .* || "$q" == */.* ]]; then
        dotfile_filter="cat"  # no-op
      else
        dotfile_filter="grep -vE '(/\.|\^\.)'"
      fi

      while IFS= read -r f; do
        [ -n "$f" ] && matches+=("@$f")
      # Prune massive/unwanted directories, and don't show hidden files/folders unless queried
      done < <(find . -type d \( -name ".git" -o -name "node_modules" -o -name "__pycache__" -o -name "venv" -o -name ".venv" -o -name "dist" -o -name "build" \) -prune -o -type f -print 2>/dev/null | sed 's|^\./||' | eval "$dotfile_filter" | grep -iE "(^|/)$q")
    else
      # No completion for regular text — just let readline handle it (no-op)
      return 0
    fi

    if (( ${#matches[@]} == 1 )); then
      # Single match — reset cycle state, fill with trailing space (or / for dirs)
      local new_word="${matches[0]}"
      local raw_path="${new_word#@}"
      if [[ -d "$raw_path" && ! "$new_word" == */ ]]; then
        new_word="$new_word/"
      elif [[ ! "$new_word" == */ ]]; then
        new_word="$new_word "
      fi
      printf '%s\n' "0" "" "" "" > "$_TAB_STATE_FILE"
      READLINE_LINE="${pre}${new_word}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$((${#pre} + ${#new_word}))
    elif (( ${#matches[@]} > 1 )); then
      # ── Step 1: try to extend to the longest common prefix ────────────
      local common="${matches[0]}"
      for m in "${matches[@]:1}"; do
        local new_common=""
        local i=0
        while (( i < ${#common} && i < ${#m} )) && [[ "${common:$i:1}" == "${m:$i:1}" ]]; do
          new_common+="${common:$i:1}"
          (( i++ )) || true
        done
        common="$new_common"
      done
      # If common prefix is longer than what's typed, fill it in and save it as new query
      if [[ ${#common} -gt ${#match_word} ]]; then
        READLINE_LINE="${pre}${common}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((${#pre} + ${#common}))
        # Save common as both query AND candidate — next Tab will continue cycling from here
        printf '%s\n' "0" "$common" "$common" "$pre" > "$_TAB_STATE_FILE"
        return 0
      fi

      # ── Step 2: no more common prefix — show menu first, then cycle ────
      if (( _tidx == 0 )); then
        # First Tab on this set of matches: show menu, next Tab fills first match
        printf '%s\n' "1" "$_tquery" "$_tquery" "$pre" > "$_TAB_STATE_FILE"
        # fall through to menu display below
      else
        # Subsequent Tabs: fill match[_tidx-1]
        local cand="${matches[$(( _tidx - 1 ))]}"
        local raw_path="${cand#@}"
        if [[ -d "$raw_path" && ! "$cand" == */ ]]; then cand="$cand/"; fi
        READLINE_LINE="${pre}${cand}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((${#pre} + ${#cand}))
        # When last match filled, wrap to 0 so next Tab shows menu again
        local next_tidx=$(( _tidx < ${#matches[@]} ? _tidx + 1 : 0 ))
        printf '%s\n' "$next_tidx" "$_tquery" "$cand" "$pre" > "$_TAB_STATE_FILE"
        return 0
      fi

      echo ""
      if [[ "${matches[0]}" == /* ]]; then
        # ── Slash command menu ─────────────────────────────────────────
        declare -A _cmd_desc=(
          ["/flush"]="clear history"          ["/undo"]="undo last edit"
          ["/stash"]="stash/pop context"      ["/stats"]="token + cost stats"
          ["/refresh"]="rebuild repo map"     ["/resume"]="reload last session"
          ["/cache"]="show file cache"        ["/verify"]="auto-verify on/off"
          ["/model"]="switch model"           ["/provider"]="switch provider"
          ["/history"]="show history"         ["/caveman"]="caveman mode"
          ["/mode"]="fast/deep/plan"          ["/yolo"]="toggle auto-confirm"
          ["/config"]="show config"           ["/ext"]="manage extensions"
          ["/workers"]="list workers"         ["/worker"]="spawn worker"
          ["/subagent"]="run subagent"        ["/skill"]="load skill"
          ["/skills"]="list skills"           ["/sandbox"]="sandbox control"
          ["/sandbox install"]="  ↳ install pkg into sandbox"
          ["/spec"]="spec-driven dev"        ["/build"]="run build tasks"
          ["/check"]="check spec"            ["/test"]="run tests"
          ["/help"]="all commands"           ["/exit"]="quit"
        )
        local _bar="────────────────────────────────────────────────────"
        echo -e "  \033[0;90m┌─ commands ${_bar:0:41}┐\033[0m"
        for m in "${matches[@]}"; do
          local desc="${_cmd_desc[$m]:-}"
          # indent sub-commands (those with spaces like "/sandbox install")
          if [[ "$m" == *" "* ]]; then
            printf "  \033[0;90m│\033[0m  \033[0;90m%-26s %s\033[0m\n" "$m" "$desc"
          else
            printf "  \033[0;90m│\033[0m  \033[1;37m%-26s\033[0m \033[0;90m%s\033[0m\n" "$m" "$desc"
          fi
        done
        echo -e "  \033[0;90m└─${_bar:0:50}┘\033[0m"
      elif [[ "${matches[0]}" == @* ]]; then
        # ── File/context menu ──────────────────────────────────────────
        # Separate special shortcuts from regular files
        local special=() regular=()
        for m in "${matches[@]}"; do
          local raw="${m#@}"
          if [[ "$raw" == git:* || "$raw" == "memory" ]]; then
            special+=("$m")
          else
            regular+=("$m")
          fi
        done
        local _bar="────────────────────────────────────────────────────"
        echo -e "  \033[0;90m┌─ context + files ${_bar:0:34}┐\033[0m"
        # Special shortcuts section
        if (( ${#special[@]} > 0 )); then
          echo -e "  \033[0;90m│  context shortcuts:\033[0m"
          for m in "${special[@]}"; do
            local raw="${m#@}"
            local sdesc=""
            case "$raw" in
              git:diff)   sdesc="staged + unstaged changes" ;;
              git:log)    sdesc="recent commit history" ;;
              git:status) sdesc="working tree status" ;;
              memory)     sdesc="global agent memory" ;;
            esac
            printf "  \033[0;90m│\033[0m  \033[1;33m%-22s\033[0m \033[0;90m%s\033[0m\n" "$m" "$sdesc"
          done
          (( ${#regular[@]} > 0 )) && echo -e "  \033[0;90m│  files:\033[0m"
        fi
        # Regular files — 2-column layout
        local col_w=26 cols=2 i=0
        for m in "${regular[@]}"; do
          local raw="${m#@}"
          local label
          if [[ -d "$raw" ]]; then
            label="\033[1;34m${m}/\033[0m"
          else
            # dim directories in path, highlight filename
            local dir part; dir=$(dirname "$raw"); part=$(basename "$raw")
            if [[ "$dir" == "." ]]; then
              label="\033[0;37m${m}\033[0m"
            else
              label="\033[0;90m@${dir}/\033[0m\033[0;37m${part}\033[0m"
            fi
          fi
          if (( i % cols == 0 )); then printf "  \033[0;90m│\033[0m  "; fi
          printf "%-$((col_w + 20))b" "$label"
          (( i++ )) || true
          (( i % cols == 0 )) && echo ""
        done
        (( i % cols != 0 )) && echo ""
        echo -e "  \033[0;90m└─${_bar:0:50}┘\033[0m"
      else
        printf "  %s\n" "${matches[@]}"
      fi
    fi
  }

  # Hook TAB directly inside Readline for read -e
  bind -x '"\t": _mix_bind_tab' 2>/dev/null || true

  # enable-bracketed-paste: tells readline to treat pasted text as single input, not execute each line
  bind 'set enable-bracketed-paste on' 2>/dev/null || true

  # ── Readline input history (Up/Down arrow cycling) ──────────────
  _INPUT_HISTFILE="${HOME}/.mix/input_history"
  _INPUT_HISTSIZE=500
  HISTFILE="$_INPUT_HISTFILE"
  HISTSIZE="$_INPUT_HISTSIZE"
  HISTFILESIZE="$_INPUT_HISTSIZE"
  HISTCONTROL="ignorespace:erasedups"
  # Load saved history (ignore errors — missing file is fine)
  history -r "$_INPUT_HISTFILE" 2>/dev/null || true
  # Deduplicate existing in-memory history
  history -n 2>/dev/null || true

  # Hook Ctrl+V to paste media (image or text) from system clipboard (if available)
  _mix_paste_media() {
    local dir="/tmp/mix-clipboard"
    mkdir -p "$dir"
    local f="$dir/img_$(date +%s).png"
    local has_img=false
    local has_txt=false
    local txt=""

    if command -v wl-paste >/dev/null 2>&1; then
      if wl-paste -l 2>/dev/null | grep -qE 'image/(png|jpeg|jpg)'; then
        wl-paste -t image/png > "$f" 2>/dev/null && has_img=true
      fi
      if [ "$has_img" = false ]; then
        txt=$(wl-paste -n 2>/dev/null) && [ -n "$txt" ] && has_txt=true
      fi
    elif command -v xclip >/dev/null 2>&1; then
      if xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -qE 'image'; then
        xclip -selection clipboard -t image/png -o > "$f" 2>/dev/null && has_img=true
      fi
      if [ "$has_img" = false ]; then
        txt=$(xclip -selection clipboard -o 2>/dev/null) && [ -n "$txt" ] && has_txt=true
      fi
    elif command -v osascript >/dev/null 2>&1; then
      # macOS
      osascript -e "try" -e "write (the clipboard as «class PNGf») to (open for access POSIX file \"$f\" with write permission)" -e "end try" >/dev/null 2>&1
      if [ -s "$f" ]; then
        has_img=true
      else
        txt=$(pbpaste 2>/dev/null) && [ -n "$txt" ] && has_txt=true
      fi
    fi

    if [ "$has_img" = true ]; then
      local insert="[image: $f] "
      READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${insert}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$((READLINE_POINT + ${#insert}))
    elif [ "$has_txt" = true ]; then
      local total_lines
      total_lines=$(printf '%s\n' "$txt" | wc -l)
      if [ "$total_lines" -gt 5 ] || [ "${#txt}" -gt 250 ]; then
        local pid=$(date +%s%N)
        printf '%s' "$txt" > "$dir/txt_$pid.txt"
        local insert="[paste _$pid: $total_lines lines] "
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${insert}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#insert}))
      else
        # Small text, just insert it normally
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${txt}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#txt}))
      fi
    else
      printf "\n  \033[0;90m(No clipboard tool. Install wl-paste or xclip, or use /paste)\033[0m\n"
    fi
  }

  # Ctrl+E — open editor (vim) to edit current input line
  _mix_edit_prompt() {
    local tmpf="/tmp/mix-prompt-$$.md"
    printf '%s\n' "$READLINE_LINE" > "$tmpf"
    local editor="${EDITOR:-vim}"
    # Save cursor, clear line, move to col 0 so editor renders cleanly
    tput sc 2>/dev/null
    $editor "$tmpf" < /dev/tty > /dev/tty 2>&1
    tput rc 2>/dev/null
    local edited
    edited="$(cat "$tmpf")"
    rm -f "$tmpf"
    # Strip trailing newline vim adds
    edited="${edited%$'\n'}"
    READLINE_LINE="$edited"
    READLINE_POINT=${#READLINE_LINE}
  }

  # Unbind lnext (literal next) from Ctrl+V so readline can receive it natively
  stty lnext undef 2>/dev/null || true

  bind -x '"\C-v": _mix_paste_media' 2>/dev/null || true
  bind -x '"\C-e": _mix_edit_prompt' 2>/dev/null || true
fi

while true; do
  if [ "$INTERACTIVE" = true ]; then
    # Format skills for display: just basename, comma separated, limited length
    _skill_status=""
    if [ -n "$ACTIVE_SKILLS" ]; then
      _s_names=""
      for _s in $ACTIVE_SKILLS; do
        _bn=$(basename "$_s" .md)
        _s_names+="${_bn},"
      done
      _skill_status="\033[0;90m(${_s_names%,})\033[0m "
    fi

    read -e -r -p $'\001'"$_skill_status"$'\033[1;37m\002❯ \001\033[0m\002' INPUT < /dev/tty || {
      # If interrupted by SIGINT (read returns >128 status code), just continue the loop
      if [ $? -gt 128 ]; then
        continue
      else
        break
      fi
    }
    # Drain any continuation lines from a raw terminal paste (Ctrl+Shift+V bypasses
    # bracketed-paste mode and sends newlines literally into /dev/tty, so read only
    # catches the first line). Collect the rest within a 60ms window.
    if IFS= read -r -t 0.06 _extra_line < /dev/tty 2>/dev/null; then
      INPUT+=$'\n'"$_extra_line"
      while IFS= read -r -t 0.06 _extra_line < /dev/tty 2>/dev/null; do
        INPUT+=$'\n'"$_extra_line"
      done
    fi
  else
    # Piped mode: read from stdin, exit after one task
    read -r INPUT || break
    # In piped mode, auto-confirm everything
    AUTO_YES=true
  fi
  INPUT="${INPUT#"${INPUT%%[![:space:]]*}"}"  # trim leading whitespace
  INPUT="${INPUT%"${INPUT##*[![:space:]]}"}"  # trim trailing whitespace
  [ -z "$INPUT" ] && continue

  # Post-read paste collapse: if INPUT is multiline (Ctrl+Shift+V paste),
  # erase the pasted lines from the terminal and replace with a clean token.
  _paste_lines=$(printf '%s\n' "$INPUT" | wc -l)
  if [ "$_paste_lines" -gt 5 ]; then
    _paste_pid="bp_$(date +%s%N)"
    mkdir -p /tmp/mix-clipboard
    printf '%s' "$INPUT" > "/tmp/mix-clipboard/txt_${_paste_pid}.txt"
    # Move cursor up _paste_lines rows, erase to bottom, reprint a clean summary
    printf '\e[%dA\e[J❯ \033[0;90m[paste %d lines — hidden]\033[0m\n' "$_paste_lines" "$_paste_lines" > /dev/tty
    INPUT="[paste _${_paste_pid}: ${_paste_lines} lines]"
  fi

  if handle_cmd "$INPUT"; then continue; fi

  # Expand @context shortcuts before sending to LLM
  # @git:diff, @git:log, @git:status → inline content block
  # @memory → inject ~/.mix/memory.md
  if [[ "$INPUT" == *"@git:diff"* ]]; then
    local _gd; _gd=$(cd "${WORKDIR:-$PWD}" && git diff 2>/dev/null | head -200) || _gd="(no diff)"
    INPUT="${INPUT//@git:diff/$'\n```diff\n'"${_gd}"$'\n```'}"
  fi
  if [[ "$INPUT" == *"@git:log"* ]]; then
    local _gl; _gl=$(cd "${WORKDIR:-$PWD}" && git log --oneline -20 2>/dev/null) || _gl="(no log)"
    INPUT="${INPUT//@git:log/$'\n```\n'"${_gl}"$'\n```'}"
  fi
  if [[ "$INPUT" == *"@git:status"* ]]; then
    local _gs; _gs=$(cd "${WORKDIR:-$PWD}" && git status 2>/dev/null) || _gs="(no status)"
    INPUT="${INPUT//@git:status/$'\n```\n'"${_gs}"$'\n```'}"
  fi
  if [[ "$INPUT" == *"@memory"* ]]; then
    local _gm_file="${HOME}/.mix/memory.md"
    local _gm_content; _gm_content=$([ -f "$_gm_file" ] && cat "$_gm_file" || echo "(memory empty)")
    INPUT="${INPUT//@memory/$'\n```\n'"${_gm_content}"$'\n```'}"
  fi

  # Resolve paste tokens back to full text before sending to LLM
  if [[ "$INPUT" == *"[paste _"* ]]; then
    INPUT=$(printf '%s' "$INPUT" | python3 -c '
import sys, re
out = sys.stdin.read()
def repl(m):
    try:
        return open("/tmp/mix-clipboard/txt_" + m.group(1) + ".txt").read()
    except:
        return m.group(0)
print(re.sub(r"\[paste _([a-zA-Z0-9_]+): [^\]]+\]", repl, out), end="")
')
  fi

  run_agent "$INPUT"
  _LAST_INPUT="$INPUT"
  echo ""  # spacing before next prompt
  echo -e "  \033[0;90m───────────────────────────────────────────────────\033[0m"  # turn separator
  echo ""

  # Piped mode: exit after processing one task
  [ "$INTERACTIVE" = false ] && break
done
