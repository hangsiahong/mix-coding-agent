# ─── Main REPL ───────────────────────────────────────────────────────────────
# Detect if we're interactive (tty) or piped
if [ -t 0 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# Trap SIGINT (Ctrl+C) to cancel current turn and return to prompt instead of exiting
trap 'echo -e "\n  \033[1;31m(Turn Cancelled)\033[0m"' SIGINT

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

  # Hook Ctrl+V to paste image from clipboard
  _mix_paste_image() {
    local dir="/tmp/mix-clipboard"
    mkdir -p "$dir"
    local f="$dir/img_$(date +%s).png"
    local has_img=false

    if command -v wl-paste >/dev/null 2>&1 && wl-paste -l 2>/dev/null | grep -q image; then
      wl-paste -t image/png > "$f" 2>/dev/null && has_img=true
    elif command -v xclip >/dev/null 2>&1 && xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q image; then
      xclip -selection clipboard -t image/png -o > "$f" 2>/dev/null && has_img=true
    elif command -v osascript >/dev/null 2>&1; then
      osascript -e "try" -e "write (the clipboard as «class PNGf») to (open for access POSIX file \"$f\" with write permission)" -e "end try" >/dev/null 2>&1
      [ -s "$f" ] && has_img=true
    fi

    if [ "$has_img" = true ]; then
      local insert="[image: $f] "
      READLINE_LINE="${READLINE_LINE:0:$READLINE_POINT}${insert}${READLINE_LINE:$READLINE_POINT}"
      READLINE_POINT=$((READLINE_POINT + ${#insert}))
    else
      # Just warn inline, will not mess up prompt entirely
      echo -e "\n  \033[0;90m(No image found in clipboard or missing xclip/wl-paste)\033[0m"
    fi
  }

  # Unbind lnext (literal next) from Ctrl+V so readline can receive it natively
  stty lnext undef 2>/dev/null || true

  bind -x '"\C-v": _mix_paste_image' 2>/dev/null || true
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
    echo -e "  \033[0;90m[${#INPUT} chars] ${INPUT:0:120}...\033[0m"
  fi

  if handle_cmd "$INPUT"; then continue; fi
  run_agent "$INPUT"
  echo ""  # spacing before next prompt

  # Piped mode: exit after processing one task
  [ "$INTERACTIVE" = false ] && break
done
