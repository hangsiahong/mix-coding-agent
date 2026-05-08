# ─── Process one tool call ──────────────────────────────────────────────────
# args: tc_line [silent_mode: "true"|"false"]
process_tc() {
  local tc_line="$1"
  local silent="${2:-false}"
  local rest="${tc_line#TC:}"
  local tid="${rest%%|||*}"
  rest="${rest#*|||}"
  local tname="${rest%%|||*}"
  local targs="${rest#*|||}"

  [ "$silent" != "true" ] && echo -e "    \033[38;5;99m$I_TOOL\033[0m \033[1;36m$tname\033[0m"

  local result=""
  case "$tname" in
    bash)
      local cmd
      cmd=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])' 2>/dev/null) || cmd="?"

      if [ "$silent" != "true" ]; then
        local total_lines
        total_lines=$(printf '%s\n' "$cmd" | wc -l)
        if [ "$total_lines" -gt 15 ]; then
          local disp_cmd
          disp_cmd=$(printf '%s\n' "$cmd" | head -n 15)
          printf "      \033[0;90m\$ %s\033[0m\n" "$disp_cmd" | sed '2,$s/^/        /'
          echo -e "         \033[0;90m... ($((total_lines - 15)) more lines)\033[0m"
        else
          printf "      \033[0;90m\$ %s\033[0m\n" "$cmd" | sed '2,$s/^/        /'
        fi
      fi

      local _risk _reason
      read -r _risk _reason <<< "$(score_risk "$cmd")"
      # Risk label
      if [ "$silent" != "true" ]; then
        case "$_risk" in
          BLOCKED) echo -e "    \033[1;31m$I_BLOCKED  BLOCKED: $_reason\033[0m" ;;
          HIGH)    echo -e "    \033[1;31m$I_WARN   Risk: HIGH ($_reason)\033[0m" ;;
          MED)
            if [ "$AUTO_YES" = "true" ]; then
              echo -e "    \033[1;33m$I_RISK_MED   Risk: MED  ($_reason) \033[0;90m[yolo: auto-confirmed]\033[0m"
            else
              echo -e "    \033[1;33m$I_RISK_MED   Risk: MED  ($_reason)\033[0m"
            fi
            ;;
        esac
      fi
      local _run=false
      if [ "$_risk" = "BLOCKED" ]; then
        result="Error: command blocked — $_reason."
        FAIL_STREAK=$((FAIL_STREAK + 1))
      elif [ "$_risk" = "HIGH" ]; then
        if [ "$silent" = "true" ]; then
           result="Error: HIGH risk command cannot be run in parallel/silent mode."
        else
           local _ans=""
           printf '    \033[1;31mType YES to confirm: \033[0m'
           read -r _ans < /dev/tty 2>/dev/null || _ans=""
           if [ "$_ans" = "YES" ]; then _run=true
           else result="User declined (HIGH risk)."; fi
        fi
      elif [ "$_risk" = "MED" ]; then
        if [ "$AUTO_YES" = "true" ]; then
          _run=true
        elif [ "$silent" = "true" ]; then
          result="Error: MED risk command requires interactive confirmation."
        elif confirm "    Run? [Y/n] "; then
          _run=true
        else
          result="User declined.";
        fi
      else
        _run=true  # LOW: auto-run
      fi
      if [ "$_run" = true ]; then
        _TOOLS_USED=$((_TOOLS_USED + 1))
        # Use bash_with_heal for auto-recovery, or bash for direct execution
        result=$(run_tool bash_with_heal "$targs")
        if [[ "$result" == "[FAILED"* ]]; then
          FAIL_STREAK=$((FAIL_STREAK + 1))
          [ "$silent" != "true" ] && echo -e "    \033[1;31m$I_FAIL failed (streak: $FAIL_STREAK/$MAX_FAIL_STREAK)\033[0m"
          local _logs; _logs=$(auto_read_logs "$result")
          [ -n "$_logs" ] && result="$result
$_logs"
          if [ "$FAIL_STREAK" -ge "$MAX_FAIL_STREAK" ]; then
            [ "$silent" != "true" ] && echo -e "    \033[1;33m$I_WARN  $FAIL_STREAK consecutive failures — injecting fallback hint\033[0m"
            local _rh="[RECOVERY HINT: $FAIL_STREAK consecutive failures. Try: different approach, check deps/permissions, simpler fallback, or tell user you're stuck."
            [ -f "$WORKDIR/SPEC.md" ] && _rh+=" Root cause known? Suggest: /spec bug: <cause> to log §B entry + §V invariant."
            _rh+="]"
            result="$result
$_rh"
          fi
        else
          FAIL_STREAK=0
          _ext_hook on_bash "$cmd"
        fi
      fi
      ;;
    read_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_READ $p\033[0m"
      result=$(run_tool read_file "$targs")
      FAIL_STREAK=0
      ;;
    edit_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      if [ "$silent" = "true" ]; then
         result="Error: edit_file cannot be run in parallel/silent mode."
      else
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
            _ext_hook on_edit "$p"
            if [ "$GIT_ENABLED" = true ]; then
              git -C "$WORKDIR" add "$p" 2>/dev/null || true
              local _gdiff
              _gdiff=$(git -C "$WORKDIR" --no-pager diff --staged --stat "$p" 2>/dev/null | head -5)
              [ -n "$_gdiff" ] && echo -e "    \033[0;90m$_gdiff\033[0m"
              _TURN_STAGED_FILES="${_TURN_STAGED_FILES:-} $p"
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
      fi
      ;;
    list_files)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_DIR $p\033[0m"
      result=$(run_tool list_files "$targs")
      FAIL_STREAK=0
      ;;
    create_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_WRITE $p (new file)\033[0m"
      if [ "$silent" = "true" ]; then
        result="Error: create_file cannot be run in parallel/silent mode."
      else
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
            _ext_hook on_create "$p"
            git -C "$WORKDIR" add "$p" 2>/dev/null || true
            _TURN_STAGED_FILES="${_TURN_STAGED_FILES:-} $p"
          fi
        else
          result="User declined create."
          FAIL_STREAK=${FAIL_STREAK:-0}
        fi
      fi
      ;;
    search_files)
      local spat; spat=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["pattern"])' 2>/dev/null) || spat="?"
      local sdir; sdir=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || sdir="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_FIND /$spat/ in $sdir\033[0m"
      result=$(run_tool search_files "$targs")
      FAIL_STREAK=0
      ;;
    update_global_memory)
      local _gm_act; _gm_act=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("action","append"))' 2>/dev/null) || _gm_act="append"
      local _gm_txt; _gm_txt=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("content",""))' 2>/dev/null) || _gm_txt="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_MEMORY global memory ($_gm_act): ${_gm_txt:0:60}\033[0m"
      result=$(run_tool update_global_memory "$targs")
      FAIL_STREAK=0
      ;;
    *)
      # Try extension tools before reporting unknown
      local _ext_result
      _ext_result=$(_ext_dispatch_tool "$tname" "$targs" 2>/dev/null) || true
      if [ -n "$_ext_result" ]; then
        result="$_ext_result"
      else
        result="Unknown: $tname"
      fi
      ;;
  esac
  [ -z "$result" ] && result="(no output)"

  # Guard against massive outputs that cause API 400 Bad Request
  # Limit total response size to 16KB per tool call in history to save tokens.
  local byte_len
  byte_len=$(printf '%s' "$result" | wc -c)
  if [ "$byte_len" -gt 16000 ]; then
    result="$(printf '%s' "$result" | head -c 16000)
... [TRUNCATED: Output exceeded 16KB ($byte_len bytes). Use read_file on specific parts if needed.]"
  fi

  if [ "$silent" != "true" ]; then
    # Extract and display VERIFY results prominently
    if printf '%s' "$result" | grep -q '\[VERIFY:'; then
      local _verify_part
      _verify_part=$(printf '%s' "$result" | sed -n '/\[VERIFY:/,$ p')
      if printf '%s' "$_verify_part" | grep -q 'FAILED'; then
        echo -e "    \033[1;31m$I_VERIFY verify:\033[0m"
      else
        echo -e "    \033[0;32m$I_VERIFY verify:\033[0m"
      fi
      printf '%s' "$_verify_part" | head -10 | while IFS= read -r _vl; do
        echo -e "      \033[0;90m$_vl\033[0m"
      done
    fi
    # Extract and display SUGGESTION results for edit failures
    if printf '%s' "$result" | grep -q '\[SUGGESTION\]'; then
      local _suggest_part
      _suggest_part=$(printf '%s' "$result" | sed -n '/\[SUGGESTION\]/,$ p' | head -15)
      echo -e "    \033[1;35m💡 suggestion:\033[0m"
      printf '%s' "$_suggest_part" | while IFS= read -r _sl; do
        echo -e "      \033[0;95m$_sl\033[0m"
      done
    fi
    # Simplify tool result text nicely aligned
    local display_res="${result:0:300}"
    display_res=$(printf '%s' "$display_res" | tr '\n' ' ')
    echo -e "      \033[38;5;244m└─ ${display_res}\033[0m"
    [ ${#result} -gt 300 ] && echo -e "         \033[0;90m... (${#result} bytes)\033[0m"

    # Append tool result to history
    local esc
    esc=$(printf '%s' "$result" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null) || esc='"(error)"'
    append_raw "{\"role\":\"tool\",\"tool_call_id\":\"$tid\",\"name\":\"$tname\",\"content\":$esc}"
  else
    printf '%s' "$result"
  fi
}