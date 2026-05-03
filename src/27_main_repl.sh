# ─── Main REPL ───────────────────────────────────────────────────────────────
# Detect if we're interactive (tty) or piped
if [ -t 0 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# Trap SIGINT (Ctrl+C) to cancel current turn and return to prompt instead of exiting
trap 'echo -e "\n  \033[1;31m(Turn Cancelled)\033[0m"' SIGINT
# Cleanup trap for crashes and exits (R1, R2)
trap 'stop_spinner 2>/dev/null; rm -f /tmp/mix-* 2>/dev/null; exit' EXIT TERM HUP

# ─── Autocomplete ─────────────────────────────────────────────

if [ "$INTERACTIVE" = true ]; then
  _mix_bind_tab() {
    local cur="${READLINE_LINE:0:$READLINE_POINT}"
    local word="${cur##* }"
    local pre="${cur:0:$((READLINE_POINT - ${#word}))}"
    local matches=()
    
    if [[ "$word" == /* ]]; then
      for c in "/flush" "/model" "/history" "/caveman" "/mode" "/yolo" "/workers" "/worker" "/subagent" "/skill" "/skills" "/help" "/exit" "/spec" "/build" "/check"; do
        [[ "$c" == "$word"* ]] && matches+=("$c")
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
        [[ "$s" == "$word"* ]] && matches+=("$s")
      done
    elif [[ "$word" == @* ]]; then
      local q="${word#@}"
      
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
      # standard bash file completion
      while IFS= read -r f; do
        [ -n "$f" ] && matches+=("$f")
      done < <(compgen -f -- "$word")
    fi

    if (( ${#matches[@]} == 1 )); then
      local new_word="${matches[0]}"
      
      # Determine if a directory to add suffix
      # We check the raw path by removing @ if present
      local raw_path="${new_word#@}"
      if [[ -d "$raw_path" && ! "$raw_path" == */ ]]; then
        new_word="$new_word/"
      elif [[ ! "$new_word" == */ ]]; then
        new_word="$new_word "
      fi

      READLINE_LINE="${pre}${new_word}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$((${#pre} + ${#new_word}))
    elif (( ${#matches[@]} > 1 )); then
      echo ""
      # Print nicely formatted
      printf "%s\t" "${matches[@]}"
      echo ""
    fi
  }

  # Hook TAB directly inside Readline for read -e
  bind -x '"\t": _mix_bind_tab' 2>/dev/null || true

  # Enable bracketed paste for safe multiline pasting
  bind 'set enable-bracketed-paste on' 2>/dev/null || true

  # Hook the terminal's bracketed paste (Right Click / Ctrl+Shift+V)
  _mix_bracketed_paste() {
    local raw_paste=""
    local ch=""
    # 201~ is the end bracket for bracketed paste
    while IFS= read -r -s -d '' -n 1 ch < /dev/tty || [ -n "$ch" ]; do
      raw_paste+="$ch"
      if [[ "$raw_paste" == *$'\e[201~' ]]; then
        raw_paste="${raw_paste%$'\e[201~'}"
        break
      fi
    done
    
    if [ -n "$raw_paste" ]; then
      local total_lines
      total_lines=$(printf '%s\n' "$raw_paste" | wc -l)
      if [ "$total_lines" -gt 5 ] || [ "${#raw_paste}" -gt 250 ]; then
        local pid="bp_$(date +%s%N)"
        local dir="/tmp/mix-clipboard"
        mkdir -p "$dir"
        printf '%s' "$raw_paste" > "$dir/txt_$pid.txt"
        local insert="[paste _$pid: $total_lines lines] "
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${insert}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#insert}))
      else
        READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${raw_paste}${READLINE_LINE:$READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#raw_paste}))
      fi
    fi
  }

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
      # Just warn inline, will not mess up prompt entirely
      echo -e "\n  \033[0;90m(Clipboard empty or unable to read)\033[0m"
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
  bind '"\e[200~": ""' # disable default bracketed paste start
  bind -x '"\e[200~": _mix_bracketed_paste' 2>/dev/null || true
fi

while true; do
  if [ "$INTERACTIVE" = true ]; then
    read -e -r -p $'\001\033[1;37m\002❯ \001\033[0m\002' INPUT < /dev/tty || {
      # If interrupted by SIGINT (read returns >128 status code), just continue the loop
      if [ $? -gt 128 ]; then
        continue
      else
        break
      fi
    }
  else
    # Piped mode: read from stdin, exit after one task
    read -r INPUT || break
    # In piped mode, auto-confirm everything
    AUTO_YES=true
  fi
  INPUT="${INPUT#"${INPUT%%[![:space:]]*}"}"  # trim leading whitespace
  INPUT="${INPUT%"${INPUT##*[![:space:]]}"}"  # trim trailing whitespace
  [ -z "$INPUT" ] && continue

  # Show truncated preview for long pastes
  if [ ${#INPUT} -gt 200 ]; then
    _prev=$(printf "%s" "$INPUT" | tr '\n' ' ' | cut -c1-80); echo -e "  \033[90m[${#INPUT} chars] ${_prev}...\033[0m"
  fi

  if handle_cmd "$INPUT"; then continue; fi
  
  # Check if handle_cmd modified INPUT (like /paste does)
  if [[ "$INPUT" == *"[paste_"* ]]; then
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
  echo ""  # spacing before next prompt

  # Piped mode: exit after processing one task
  [ "$INTERACTIVE" = false ] && break
done
