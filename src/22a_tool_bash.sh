_tc_bash() {
  local targs="$1" silent="$2" total_count="$3" cur_idx="$4" tid="$5"
  local cmd _res=""
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
    _res="Error: command blocked — $_reason."
    FAIL_STREAK=$((FAIL_STREAK + 1))
  elif [ "$_risk" = "HIGH" ]; then
    if [ "$silent" = "true" ]; then
       _res="Error: HIGH risk command cannot be run in parallel/silent mode."
    else
       local _ans=""
       printf '    \033[1;31mType YES to confirm: \033[0m'
       read -r _ans < /dev/tty 2>/dev/null || _ans=""
       if [ "$_ans" = "YES" ]; then _run=true
       else _res="User declined (HIGH risk)."; fi
    fi
  elif [ "$_risk" = "MED" ]; then
    if [ "$AUTO_YES" = "true" ] || [ "$_BATCH_AUTO_YES" = "true" ]; then
      _run=true
      [ "$_BATCH_AUTO_YES" = "true" ] && [ "$AUTO_YES" != "true" ] && echo -e "    \033[0;90m↳ auto-running (batch mode)\033[0m"
    elif [ "$silent" = "true" ]; then
      _res="Error: MED risk command requires interactive confirmation."
    else
      local _prompt="    Run? [Y/n"
      [ "$total_count" -gt 1 ] && [ "$cur_idx" -lt "$total_count" ] && _prompt+="/a"
      _prompt+="] "
      local _ans _rrc; read -r -p "$_prompt" _ans < /dev/tty 2>/dev/null; _rrc=$?
      [ "$_rrc" -gt 128 ] && { echo ""; _ans="n"; }  # Ctrl+C = cancel
      case "$_ans" in
        a*|A*) _BATCH_AUTO_YES=true; _run=true ;;
        n*|N*) _run=false; _res="User declined." ;;
        *) _run=true ;;
      esac
    fi
  else
    _run=true  # LOW: auto-run
  fi
  if [ "$_run" = true ]; then
    _TOOLS_USED=$((_TOOLS_USED + 1))
    _res=$(run_tool bash_with_heal "$targs")
    if [[ "$_res" == "[FAILED"* ]]; then
      FAIL_STREAK=$((FAIL_STREAK + 1))
      [ "$silent" != "true" ] && echo -e "    \033[1;31m$I_FAIL failed (streak: $FAIL_STREAK/$MAX_FAIL_STREAK)\033[0m"
      local _logs; _logs=$(auto_read_logs "$_res")
      [ -n "$_logs" ] && _res="$_res
$_logs"
      if [ "$FAIL_STREAK" -ge "$MAX_FAIL_STREAK" ]; then
        [ "$silent" != "true" ] && echo -e "    \033[1;33m$I_WARN  $FAIL_STREAK consecutive failures — injecting fallback hint\033[0m"
        local _rh="[RECOVERY HINT: $FAIL_STREAK consecutive failures. Try: different approach, check deps/permissions, simpler fallback, or tell user you're stuck."
        [ -f "$WORKDIR/SPEC.md" ] && _rh+=" Root cause known? Suggest: /spec bug: <cause> to log §B entry + §V invariant."
        _rh+="]"
        _res="$_res
$_rh"
      fi
    else
      FAIL_STREAK=0
      _ext_hook on_bash "$cmd"
    fi
  fi
  printf '%s' "$_res"
}
