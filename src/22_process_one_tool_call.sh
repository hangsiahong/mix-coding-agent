# ─── Process one tool call ──────────────────────────────────────────────────
# args: tc_line [silent_mode: "true"|"false"] [current_idx] [total_count]
process_tc() {
  local tc_line="$1"
  local silent="${2:-false}"
  local cur_idx="${3:-1}"
  local total_count="${4:-1}"
  local rest="${tc_line#TC:}"
  local tid="${rest%%|||*}"
  rest="${rest#*|||}"
  local tname="${rest%%|||*}"
  local targs="${rest#*|||}"

  if [ "$silent" != "true" ]; then
    local _batch_prefix=""
    [ "$total_count" -gt 1 ] && _batch_prefix="\033[0;90m[$cur_idx/$total_count]\033[0m "
    echo -e "    ${_batch_prefix}\033[38;5;99m$I_TOOL\033[0m \033[1;36m$tname\033[0m"
  fi

  local result=""
  case "$tname" in
    bash)
      result=$(_tc_bash "$targs" "$silent" "$total_count" "$cur_idx" "$tid")
      ;;
    read_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_READ $p\033[0m"
      result=$(run_tool read_file "$targs")
      FAIL_STREAK=0
      ;;
    edit_file)
      result=$(_tc_edit_file "$targs" "$silent" "$total_count" "$cur_idx" "$tid")
      ;;
    list_files)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_DIR $p\033[0m"
      result=$(run_tool list_files "$targs")
      FAIL_STREAK=0
      ;;
    send_message)
      local t m; t=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["to"])' 2>/dev/null) || t="?"
      m=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["message"])' 2>/dev/null) || m="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_MAIL sending message to $t\033[0m"
      result=$(run_tool send_message "$targs")
      ;;
    read_messages)
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_MAIL checking inbox\033[0m"
      result=$(run_tool read_messages "$targs")
      ;;
    find_definition)
      local s; s=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["symbol"])' 2>/dev/null) || s="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_SEARCH finding definition: $s\033[0m"
      result=$(run_tool find_definition "$targs")
      ;;
    check_job)
      local jid; jid=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["job_id"])' 2>/dev/null) || jid="?"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_READ checking job $jid\033[0m"
      result=$(run_tool check_job "$targs")
      ;;
    delete_file)
      local p; p=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["path"])' 2>/dev/null) || p="?"
      if [ "$silent" = "true" ]; then
        result="Error: delete_file cannot be run in parallel/silent mode."
      else
        echo -e "      \033[1;31m$I_WARN   Deleting: $p\033[0m"
        if confirm "    Delete file? [y/N] " "n"; then
          result=$(run_tool delete_file "$targs")
          _TOOLS_USED=$((_TOOLS_USED + 1))
        else
          result="User declined deletion."
        fi
      fi
      ;;
    move_file)
      local s d; s=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["source"])' 2>/dev/null) || s="?"
      d=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin)["destination"])' 2>/dev/null) || d="?"
      if [ "$silent" = "true" ]; then
        result="Error: move_file cannot be run in parallel/silent mode."
      else
        echo -e "      \033[0;36mMoving: $s -> $d\033[0m"
        if confirm "    Move file? [Y/n] "; then
          result=$(run_tool move_file "$targs")
          _TOOLS_USED=$((_TOOLS_USED + 1))
        else
          result="User declined move."
        fi
      fi
      ;;
    create_files)
      if [ "$silent" = "true" ]; then
        result="Error: create_files cannot be run in parallel/silent mode."
      else
        echo -e "      \033[0;90mCreating multiple files...\033[0m"
        printf '%s' "$targs" | python3 -c '
import json,sys
d=json.load(sys.stdin)
files=d.get("files",{})
GRN,RST="\033[0;32m","\033[0m"
for i, (path, content) in enumerate(files.items()):
    if i >= 5:
        print(f"      ... and {len(files)-5} more files")
        break
    print(f"      {GRN}file: {path}{RST}")
    lines = content.splitlines()
    for l in lines[:3]: print(f"        + {l}")
    if len(lines) > 3: print(f"        ... ({len(lines)-3} more lines)")
' 2>/dev/null
        local _do_create=false
        if [ "$AUTO_YES" = "true" ] || [ "$_BATCH_AUTO_YES" = "true" ]; then
          _do_create=true
          [ "$_BATCH_AUTO_YES" = "true" ] && [ "$AUTO_YES" != "true" ] && echo -e "    \033[0;90m↳ auto-creating (batch mode)\033[0m"
        else
          local _prompt="    Create files? [Y/n"
          [ "$total_count" -gt 1 ] && [ "$cur_idx" -lt "$total_count" ] && _prompt+="/a"
          _prompt+="] "
          local _ans _rrc; read -r -p "$_prompt" _ans < /dev/tty 2>/dev/null; _rrc=$?
          [ "$_rrc" -gt 128 ] && { echo ""; _ans="n"; }  # Ctrl+C = cancel
          case "$_ans" in
            a*|A*) _BATCH_AUTO_YES=true; _do_create=true ;;
            n*|N*) _do_create=false; result="User declined create_files." ;;
            *) _do_create=true ;;
          esac
        fi
        if [ "$_do_create" = "true" ]; then
          result=$(run_tool create_files "$targs")
          _TOOLS_USED=$((_TOOLS_USED + 1))
          FAIL_STREAK=0
        fi
      fi
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
        local _do_create=false
        if [ "$AUTO_YES" = "true" ] || [ "$_BATCH_AUTO_YES" = "true" ]; then
          _do_create=true
          [ "$_BATCH_AUTO_YES" = "true" ] && [ "$AUTO_YES" != "true" ] && echo -e "    \033[0;90m↳ auto-creating (batch mode)\033[0m"
        else
          local _prompt="    Create file? [Y/n"
          [ "$total_count" -gt 1 ] && [ "$cur_idx" -lt "$total_count" ] && _prompt+="/a"
          _prompt+="] "
          local _ans; read -r -p "$_prompt" _ans < /dev/tty 2>/dev/null || _ans="y"
          case "$_ans" in
            a*|A*) _BATCH_AUTO_YES=true; _do_create=true ;;
            n*|N*) _do_create=false; result="User declined create." ;;
            *) _do_create=true ;;
          esac
        fi

        if [ "$_do_create" = "true" ]; then
          result=$(run_tool create_file "$targs")
          _TOOLS_USED=$((_TOOLS_USED + 1))
          FAIL_STREAK=0
          if [[ "$result" == Created* ]] && [ "$GIT_ENABLED" = true ]; then
            _ext_hook on_create "$p"
            git -C "$WORKDIR" add "$p" 2>/dev/null || true
            _TURN_STAGED_FILES="${_TURN_STAGED_FILES:-} $p"
          fi
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
    spawn_subagent)
      local _san; _san=$(printf '%s' "$targs" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("name","subagent"))' 2>/dev/null) || _san="subagent"
      [ "$silent" != "true" ] && echo -e "    \033[0;90m$I_TOOL spawning subagent: $_san\033[0m"
      result=$(run_tool spawn_subagent "$targs")
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
  _LAST_TOOL_RESULT="$result"

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