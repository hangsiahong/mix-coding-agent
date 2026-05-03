# ─── Process one tool call ──────────────────────────────────────────────────
process_tc() {
  local tc_line="$1"
  local rest="${tc_line#TC:}"
  local tid="${rest%%|||*}"
  rest="${rest#*|||}"
  local tname="${rest%%|||*}"
  local targs="${rest#*|||}"

  echo -e "    \033[38;5;99m⚡\033[0m \033[1;36m$tname\033[0m"

  local result=""
  case "$tname" in
    bash)
      local cmd
      cmd=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || cmd="?"
      echo -e "      \033[0;90m\$ $cmd\033[0m"
      local _risk _reason
      read -r _risk _reason <<< "$(score_risk "$cmd")"
      # Risk label
      case "$_risk" in
        BLOCKED) echo -e "    \033[1;31m⛔  BLOCKED: $_reason\033[0m" ;;
        HIGH)    echo -e "    \033[1;31m⚠   Risk: HIGH ($_reason)\033[0m" ;;
        MED)     echo -e "    \033[1;33m◈   Risk: MED  ($_reason)\033[0m" ;;
      esac
      local _run=false
      if [ "$_risk" = "BLOCKED" ]; then
        result="Error: command blocked — $_reason."
        FAIL_STREAK=$((FAIL_STREAK + 1))
      elif [ "$_risk" = "HIGH" ]; then
        local _ans=""
        printf '    \033[1;31mType YES to confirm: \033[0m'
        read -r _ans < /dev/tty 2>/dev/null || _ans=""
        if [ "$_ans" = "YES" ]; then _run=true
        else result="User declined (HIGH risk)."; FAIL_STREAK=0; fi
      elif [ "$_risk" = "MED" ]; then
        if [ "$AGENT_MODE" = "yolo" ]; then
          _run=true
        elif confirm "    Run? [Y/n] "; then 
          _run=true
        else 
          result="User declined."; FAIL_STREAK=0; 
        fi
      else
        _run=true  # LOW: auto-run
      fi
      if [ "$_run" = true ]; then
        _TOOLS_USED=$((_TOOLS_USED + 1))
        result=$(run_with_heal "$cmd")
        if [[ "$result" == "[FAILED"* ]]; then
          FAIL_STREAK=$((FAIL_STREAK + 1))
          echo -e "    \033[1;31m✗ failed (streak: $FAIL_STREAK/$MAX_FAIL_STREAK)\033[0m"
          local _logs; _logs=$(auto_read_logs "$result")
          [ -n "$_logs" ] && result="$result
$_logs"
          if [ "$FAIL_STREAK" -ge "$MAX_FAIL_STREAK" ]; then
            echo -e "    \033[1;33m⚠  $FAIL_STREAK consecutive failures — injecting fallback hint\033[0m"
            local _rh="[RECOVERY HINT: $FAIL_STREAK consecutive failures. Try: different approach, check deps/permissions, simpler fallback, or tell user you're stuck."
            [ -f "$WORKDIR/SPEC.md" ] && _rh+=" Root cause known? Suggest: /spec bug: <cause> to log §B entry + §V invariant."
            _rh+="]"
            result="$result
$_rh"
          fi
        else
          FAIL_STREAK=0
        fi
      fi
      ;;
    read_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      echo -e "    \033[0;90m📄 $p\033[0m"
      result=$(run_tool read_file "$targs")
      ;;
    edit_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      echo -e "    \033[0;90m✏️  $p\033[0m"
      # Git patch mode: snapshot before, stage after, show real git diff, rollback on decline
      local _before_hash="none" _git_staged=""
      if [ "$GIT_ENABLED" = true ]; then
        # Ensure file is tracked so git diff works
        git -C "$WORKDIR" add -N "$p" 2>/dev/null || true
        _before_hash=$(git -C "$WORKDIR" rev-parse HEAD 2>/dev/null || echo "none")
      fi
      # Always show Python-computed diff first (works on new/untracked files too)
      show_edit_diff "$targs"
      if confirm "    Apply edit? [Y/n] "; then
        result=$(run_tool edit_file "$targs")
        FAIL_STREAK=0
        _TOOLS_USED=$((_TOOLS_USED + 1))
        if [[ "$result" == Edited* ]]; then
          if [ "$GIT_ENABLED" = true ]; then
            # Stage and show real git diff
            git -C "$WORKDIR" add "$p" 2>/dev/null || true
            local _gdiff
            _gdiff=$(git -C "$WORKDIR" --no-pager diff --staged --stat 2>/dev/null | head -5)
            [ -n "$_gdiff" ] && echo -e "    \033[0;90m$_gdiff\033[0m"
            # Extract a one-line summary from the tool args
            local _cmsg
            _cmsg="agent: $(printf '%s' "$targs" | python3 -c \
              'import json,sys; d=json.load(sys.stdin); print("edit "+d.get("path","").split("/")[-1])' 2>/dev/null || echo "edit $(basename "$p")")"
            if git -C "$WORKDIR" commit -m "$_cmsg" --quiet 2>/dev/null; then
              echo -e "    \033[0;90m↳ committed: $_cmsg\033[0m"
              result="$result (committed)"
            fi
          fi
          # Offer test run if test command configured
          if [ -n "$TEST_CMD" ] && confirm "    Run tests ($TEST_CMD)? [Y/n] "; then
            echo -e "    \033[0;90m↳ $TEST_CMD...\033[0m"
            local _tres; _tres=$(eval "$TEST_CMD" 2>&1 | tail -30) || true
            printf '%s\n' "$_tres" | head -8 | while IFS= read -r _tl; do
              echo -e "    \033[0;90m  $_tl\033[0m"
            done
            result="$result\n[TEST: $(printf '%s' "$_tres" | tail -3)]"
          fi
        fi
      else
        # Rollback: unstage
        if [ "$GIT_ENABLED" = true ] && [ "$_before_hash" != "none" ]; then
          git -C "$WORKDIR" checkout -- "$p" 2>/dev/null || true
          echo -e "    \033[0;90m↳ rolled back (checkout --)\033[0m"
        fi
        result="User declined edit."
      fi
      ;;
    list_files)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      echo -e "    \033[0;90m📁 $p\033[0m"
      result=$(run_tool list_files "$targs")
      ;;
    create_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      echo -e "    \033[0;90m📝 $p (new file)\033[0m"
      printf '%s' "$targs" | python3 -c '
import json,sys
d=json.load(sys.stdin)
c=d.get("content","")
GRN,RST="\033[0;32m","\033[0m"
lines=c.splitlines()
for l in lines[:15]: sys.stdout.write("    "+GRN+"+ "+l+RST+"\n")
if len(lines)>15: sys.stdout.write("    \033[0;90m... (%d more lines)\033[0m\n" % (len(lines)-15))
' 2>/dev/null
      if confirm "    Create file? [Y/n] "; then
        result=$(run_tool create_file "$targs")
        _TOOLS_USED=$((_TOOLS_USED + 1))
        FAIL_STREAK=0
        if [[ "$result" == Created* ]] && [ "$GIT_ENABLED" = true ]; then
          git -C "$WORKDIR" add "$p" 2>/dev/null || true
          git -C "$WORKDIR" commit -m "agent: create $(basename "$p")" --quiet 2>/dev/null \
            && echo -e "    \033[0;90m↳ committed: create $(basename "$p")\033[0m" \
            && result="$result (committed)" || true
        fi
      else
        result="User declined create."
        FAIL_STREAK=0
      fi
      ;;
    search_files)
      local spat; spat=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pattern"])' 2>/dev/null) || spat="?"
      local sdir; sdir=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || sdir="?"
      echo -e "    \033[0;90m🔍 /$spat/ in $sdir\033[0m"
      result=$(run_tool search_files "$targs")
      ;;
    *) result="Unknown: $tname" ;;
  esac
  [ -z "$result" ] && result="(no output)"

  # Simplify tool result text nicely aligned 
  local display_res="${result:0:300}"
  display_res=$(printf '%s' "$display_res" | tr '\n' ' ')
  echo -e "      \033[38;5;244m└─ ${display_res}\033[0m"
  [ ${#result} -gt 300 ] && echo -e "         \033[0;90m... (${#result} bytes)\033[0m"

  # Append tool result to history
  local esc
  esc=$(printf '%s' "$result" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null) || esc='"(error)"'
  append_raw "{\"role\":\"tool\",\"tool_call_id\":\"$tid\",\"name\":\"$tname\",\"content\":$esc}"
}

