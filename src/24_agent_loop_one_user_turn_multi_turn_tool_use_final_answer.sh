# ─── Agent Loop (one user turn → multi-turn tool use → final answer) ────────
run_agent() {
  local input="$1"
  compact_history  # auto-compact before adding new turn
  append_text "user" "$input"
  _TOOLS_USED=0

  # Plan mode: generate and show numbered plan, ask approval before tools
  if [ "$AGENT_MODE" = "plan" ]; then
    printf "\r\033[K  \033[1;35m📋 planning...\033[0m"
    local _plan; _plan=$(call_api_plan) || true
    if [ -n "$_plan" ]; then
      echo -e "\r\033[K  \033[0;35m━━━ Plan ━━━\033[0m"
      printf '  %s\n' "$_plan"
      echo -e "  \033[0;35m━━━━━━━━━━━\033[0m"
      local _pa; read -r -p $'  Proceed? [Y/n] ' _pa < /dev/tty 2>/dev/null || _pa="y"
      if [[ "$_pa" == n* ]]; then echo "  Aborted."; return; fi
    fi
  fi

  local turn=0
  while [ "$turn" -lt "$MAX_TURNS" ]; do
    turn=$((turn + 1))
    # Always start animated spinner (Python will kill it before streaming first token)
    start_spinner "mix (turn $turn)"
    export SPIN_PID="$_SPIN_PID"

    local parsed
    local _api_attempt _api_max_retries=3
    for _api_attempt in 1 2 3; do
      if [ "$STREAM" = "true" ]; then
        parsed=$(call_api_stream)
        if [[ "$parsed" == FAIL:network_drop* ]]; then
          [ "$INTERACTIVE" = false ] \
            && echo -e "    \033[0;90m↻ Connection dropped (attempt $_api_attempt/$_api_max_retries) — retrying without streaming...\033[0m" >&2 \
            || echo -e "    \033[0;90m↻ Connection dropped (attempt $_api_attempt/$_api_max_retries) — retrying without streaming...\033[0m" >/dev/tty 2>/dev/null
          start_spinner "turn $turn (retry $_api_attempt)"
          local resp; resp=$(call_api)
          if [[ "$resp" == FAIL:* ]]; then
            stop_spinner
            if [ "$_api_attempt" -lt "$_api_max_retries" ]; then
              echo -e "\r\033[K  \033[0;90m↻ API error, retrying...\033[0m"
              continue
            fi
            echo -e "\r\033[K  \033[1;31mAPI failed after $_api_max_retries attempts: ${resp#FAIL:}\033[0m"
            break 2
          fi
          parsed=$(parse_resp "$resp")
        fi
      else
        local resp; resp=$(call_api)
        if [[ "$resp" == FAIL:* ]]; then
          stop_spinner
          if [ "$_api_attempt" -lt "$_api_max_retries" ]; then
            echo -e "\r\033[K  \033[0;90m↻ API error (attempt $_api_attempt/$_api_max_retries), retrying...\033[0m"
            start_spinner "turn $turn (retry $_api_attempt)"
            continue
          fi
          echo -e "\r\033[K  \033[1;31mAPI failed after $_api_max_retries attempts: ${resp#FAIL:}\033[0m"
          break 2
        fi
        parsed=$(parse_resp "$resp")
      fi
      break  # success — exit retry loop
    done
    stop_spinner

    # If parsing somehow still resulted in a failure, abort
    [[ "$parsed" == FAIL:* ]] && { echo -e "  \033[1;31m${parsed#FAIL:}\033[0m"; break; }

    # Add raw assistant message to history
    local raw_b64
    raw_b64=$(printf '%s' "$parsed" | grep '^RAW:' | head -1 | sed 's/^RAW://')
    local raw_msg
    raw_msg=$(printf '%s' "$raw_b64" | base64 -d 2>/dev/null) || raw_msg='{"role":"assistant","content":""}'
    append_raw "$raw_msg"

    # Process: tool calls or final text
    local tc_lines text_line
    tc_lines=$(printf '%s' "$parsed" | grep '^TC:' || true)
    text_line=$(printf '%s' "$parsed" | grep '^TEXT:' || true)

    if [ -n "$tc_lines" ]; then
      [ "$INTERACTIVE" = false ] && printf "\r\033[K" >&2 || printf "\r\033[K" >/dev/tty 2>/dev/null  # clear spinner line

      # PARALLEL EXECUTION:
      # 1. Separate read-only (parallelizable) and write-active tools.
      # 2. Parallel tools run in subshells, results captured in temp files.
      # 3. Write tools run sequentially.

      local _batch_dir; _batch_dir=$(mktemp -d -t mix-batch-XXXXXX)
      local _tc_idx=0
      local _parallel_refs=() # format "idx|tid|tname"
      local _sequential_tcs=()

      while IFS= read -r tc; do
        [ -z "$tc" ] && continue

        # Robust parsing
        local _rest="${tc#TC:}"
        local _tid="${_rest%%|||*}"
        local _tname="${_rest#*|||}"
        _tname="${_tname%%|||*}"

        # Read-only tools can be parallelized
        if [[ "$_tname" =~ ^(read_file|list_files|search_files)$ ]]; then
          _tc_idx=$((_tc_idx + 1))
          _parallel_refs+=("$_tc_idx|$_tid|$_tname")
          (
            # Subshell: run silently and capture output
            local _res; _res=$(process_tc "$tc" "true")
            echo "$_res" > "$_batch_dir/$_tc_idx"
          ) &
          echo -e "    \033[38;5;99m⚡\033[0m \033[1;36m$_tname\033[0m \033[0;90m(parallel)\033[0m"
        else
          _sequential_tcs+=("$tc")
        fi
      done <<< "$tc_lines"

      # Wait for all parallel tools
      wait

      # Process parallel results (append to history)
      for _pref in "${_parallel_refs[@]}"; do
        local _idx="${_pref%%|*}"
        local _rest="${_pref#*|}"
        local _tid="${_rest%%|*}"
        local _tname="${_rest#*|}"
        local _res; _res=$(cat "$_batch_dir/$_idx" 2>/dev/null || echo "Error: parallel tool failed")

        # UI Feedback
        local _disp="${_res:0:120}"
        _disp=$(printf '%s' "$_disp" | tr '\n' ' ')
        echo -e "      \033[38;5;244m└─ ${_disp}...\033[0m"

        # Append to history (no disk write yet — batch them)
        local _esc
        _esc=$(printf '%s' "$_res" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null) || _esc='"(error)"'
        append_raw_nosave "{\"role\":\"tool\",\"tool_call_id\":\"$_tid\",\"name\":\"$_tname\",\"content\":$_esc}"
      done
      # Flush once for entire parallel batch + count them
      if [ "${#_parallel_refs[@]}" -gt 0 ]; then
        save_history
        _TOOLS_USED=$((_TOOLS_USED + ${#_parallel_refs[@]}))
      fi

      # Process sequential tools (bash, edit, create)
      for tc in "${_sequential_tcs[@]}"; do
        process_tc "$tc"
      done

      rm -rf "$_batch_dir"
      # Loop continues — model will see tool results and respond
    elif [ -n "$text_line" ]; then
      # streaming already printed content live to /dev/tty; skip reprint
      if [ "$STREAM" != "true" ]; then
        local final="${text_line#TEXT:}"
        printf '    %s\n\n' "$final"
      fi
      break
    else
      echo -e "\r\033[K  \033[1;31mUnexpected response\033[0m"
      break
    fi
  done

  [ "$turn" -ge "$MAX_TURNS" ] && echo -e "  \033[1;31mMax turns reached\033[0m"
  ctx_bar       # show context window usage after every agent turn
  tmux_update   # refresh tmux status bar
  # Auto-append to memorybank/log.md if memorybank exists and tools were used
  if [ "$_TOOLS_USED" -gt 0 ] && [ -f "$WORKDIR/memorybank/log.md" ]; then
    printf '\n## [%s] task | %s\n' "$(date '+%Y-%m-%d')" "${input:0:80}" \
      >> "$WORKDIR/memorybank/log.md" 2>/dev/null || true
  fi
  # Auto memorybank solution: if edit succeeded in git repo, look for "committed" marker in history
  if [ "$_TOOLS_USED" -gt 0 ] && [ "$GIT_ENABLED" = true ] && \
     [ -d "$WORKDIR/memorybank" ] && printf '%s' "$HISTORY" | grep -q '"committed"'; then
    local _slug; _slug=$(printf '%s' "$input" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-40)
    local _sfile="$WORKDIR/memorybank/solutions/${_slug}.md"
    if [ ! -f "$_sfile" ]; then
      # Extract last assistant text for a meaningful summary
      local _last_answer; _last_answer=$(printf '%s' "$HISTORY" | python3 -c '
import json,sys
h=json.load(sys.stdin)
for m in reversed(h):
  if m.get("role")=="assistant" and m.get("content"):
    print(m["content"][:500]); break
' 2>/dev/null || true)
      mkdir -p "$WORKDIR/memorybank/solutions" 2>/dev/null || true
      {
        printf '# %s\n' "$_slug"
        printf 'Date: %s\n' "$(date '+%Y-%m-%d')"
        printf 'Input: %s\n' "${input:0:200}"
        [ -n "$_last_answer" ] && printf '\n## Summary\n%s\n' "$_last_answer"
      } > "$_sfile" 2>/dev/null || true
      echo -e "  \033[0;90m✓ memorybank/solutions/${_slug}.md\033[0m"
    fi
  fi
}

