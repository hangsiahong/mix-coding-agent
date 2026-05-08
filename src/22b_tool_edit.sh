_tc_edit_file() {
  local targs="$1" silent="$2" total_count="$3" cur_idx="$4" tid="$5"
  local p _res=""
  p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
  if [ "$silent" = "true" ]; then
     _res="Error: edit_file cannot be run in parallel/silent mode."
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
    local _do_edit=false
    if [ "$AUTO_YES" = "true" ] || [ "$_BATCH_AUTO_YES" = "true" ]; then
      _do_edit=true
      [ "$_BATCH_AUTO_YES" = "true" ] && [ "$AUTO_YES" != "true" ] && echo -e "    \033[0;90m↳ auto-applying (batch mode)\033[0m"
    else
      local _prompt="    Apply edit? [Y/n"
      [ "$total_count" -gt 1 ] && [ "$cur_idx" -lt "$total_count" ] && _prompt+="/a"
      _prompt+="] "
      local _ans _rrc; read -r -p "$_prompt" _ans < /dev/tty 2>/dev/null; _rrc=$?
      [ "$_rrc" -gt 128 ] && { echo ""; _ans="n"; }  # Ctrl+C = cancel
      case "$_ans" in
        a*|A*) _BATCH_AUTO_YES=true; _do_edit=true ;;
        n*|N*) _do_edit=false; _res="User declined edit." ;;
        *) _do_edit=true ;;
      esac
    fi

    if [ "$_do_edit" = "true" ]; then
      _res=$(run_tool edit_file "$targs")
      FAIL_STREAK=0
      _TOOLS_USED=$((_TOOLS_USED + 1))
      if [[ "$_res" == Edited* ]]; then
        _ext_hook on_edit "$p"
        if [ "$GIT_ENABLED" = true ]; then
          git -C "$WORKDIR" add "$p" 2>/dev/null || true
          local _gdiff
          _gdiff=$(git -C "$WORKDIR" --no-pager diff --staged --stat "$p" 2>/dev/null | head -5)
          [ -n "$_gdiff" ] && echo -e "    \033[0;90m$_gdiff\033[0m"
          _TURN_STAGED_FILES="${_TURN_STAGED_FILES:-} $p"
        fi
        # Offer test run if test command configured AND it is the last tool in batch
        if [ -n "$TEST_CMD" ] && [ "$cur_idx" -eq "$total_count" ] && confirm "    Run tests ($TEST_CMD)? [Y/n] "; then
          echo -e "    \033[0;90m↳ $TEST_CMD...\033[0m"
          local _tres; _tres=$(eval "$TEST_CMD" 2>&1 | tail -30) || true
          printf '%s\n' "$_tres" | head -8 | while IFS= read -r _tl; do
            echo -e "    \033[0;90m  $_tl\033[0m"
          done
          _res="$_res\n[TEST: $(printf '%s' "$_tres" | tail -3)]"
        fi
      fi
    else
      # Rollback: unstage
      if [ "$GIT_ENABLED" = true ] && [ "$_before_hash" != "none" ]; then
        git -C "$WORKDIR" checkout -- "$p" 2>/dev/null || true
        echo -e "    \033[0;90m↳ rolled back (checkout --)\033[0m"
      fi
    fi
  fi
  printf '%s' "$_res"
}
