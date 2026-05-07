# ─── Auto-Commit Turn ───────────────────────────────────────────────────────
_commit_turn() {
  local _input="$1"
  [ "${GIT_ENABLED:-false}" != true ] && return 0
  [ -z "${_TURN_STAGED_FILES:-}" ] && return 0

  # Check if anything is actually staged
  if ! git -C "$WORKDIR" diff --staged --quiet 2>/dev/null; then
    local _diff_stat; _diff_stat=$(git -C "$WORKDIR" --no-pager diff --staged --stat 2>/dev/null | tail -n 1 | sed 's/^[ \t]*//')
    
    # We rely on an LLM API call to generate a top-tier conventional commit message.
    # If the user's provider is set up and we can reach it, we'll stream a small payload.
    # To keep things robust, if it fails, we fall back to a basic string manipulation approach.
    
    local _cmsg="agent: auto-commit ($_diff_stat)"
    
    # Simple conventional commit inference fallback
    local _prefix="refactor"
    local _linput
    _linput=$(echo "$_input" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$_linput" == *bug* || "$_linput" == *fix* || "$_linput" == *error* || "$_linput" == *issue* ]]; then
      _prefix="fix"
    elif [[ "$_linput" == *add* || "$_linput" == *feat* || "$_linput" == *new* || "$_linput" == *create* ]]; then
      _prefix="feat"
    elif [[ "$_linput" == *doc* || "$_linput" == *readme* ]]; then
      _prefix="docs"
    elif [[ "$_linput" == *test* ]]; then
      _prefix="test"
    fi

    local _summary; _summary=$(echo "$_input" | head -n 1 | cut -c1-60 | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')
    [ -z "$_summary" ] && _summary="auto-commit by agent"
    
    local _fallback_cmsg="$_prefix: $_summary"
    
    # Build a minimal, single-turn LLM request asking for a conventional commit.
    # We pass the diff stat and the exact git diff.
    local _diff_content
    _diff_content=$(git -C "$WORKDIR" --no-pager diff --staged 2>/dev/null | head -n 200) # clip massive diffs
    
    # Use python to construct a JSON payload quickly to ping the API directly, bypassing agent loop state
    local _commit_payload
    _commit_payload=$(printf '%s\n__DIFF_SEP__\n%s\n' "$_diff_content" "$_input" | python3 -c '
import json,sys
parts=sys.stdin.read().split("__DIFF_SEP__\n")
diff=parts[0].strip()
user_prompt=parts[1].strip() if len(parts)>1 else ""
sys_prompt="You are a senior developer. Write a precise, single-line Conventional Commit message (e.g. \"feat: add user login\", \"fix: resolve null pointer in auth\"). Read the user request and the diff below. Output ONLY the commit message line, no quotes, no markdown, no explanation."
msg=[
  {"role":"system","content":sys_prompt},
  {"role":"user","content":"User prompt: " + user_prompt + "\n\nDiff:\n" + diff}
]
print(json.dumps({"model":"'"$MODEL"'","messages":msg,"temperature":0.1}))
' 2>/dev/null)

    local _api_key="$API_KEY"
    if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_get_api_key" >/dev/null 2>&1; then
      local _pkey; _pkey=$(${PROVIDER}_get_api_key 2>/dev/null) || true
      [ -n "$_pkey" ] && _api_key="$_pkey"
    fi

    local _curl_args=(-s -w "%{http_code}" --max-time 15
      "${BASE_URL}/chat/completions"
      -H "Content-Type: application/json")
      
    # Assume standard Bearer auth for this quick call (default/openai-like)
    [ -n "$_api_key" ] && _curl_args+=(-H "Authorization: Bearer $_api_key")

    local _tmp; _tmp=$(mktemp)
    local _code
    _code=$(curl "${_curl_args[@]}" -o "$_tmp" -d "$_commit_payload" 2>/dev/null) || _code="err"
    
    local _body; _body=$(cat "$_tmp" 2>/dev/null || true); rm -f "$_tmp"
    
    if [ "$_code" = "200" ]; then
      local _ai_cmsg
      _ai_cmsg=$(printf '%s' "$_body" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    print(d["choices"][0]["message"]["content"].strip().strip("\"").strip("\'"))
except:
    pass
' 2>/dev/null)
      [ -n "$_ai_cmsg" ] && _cmsg="$_ai_cmsg" || _cmsg="$_fallback_cmsg"
    else
      _cmsg="$_fallback_cmsg"
    fi

    if git -C "$WORKDIR" commit -m "$_cmsg" --quiet 2>/dev/null; then
      local _stat_print; _stat_print="($_diff_stat)"
      echo -e "  \033[0;90m↳ commit: $_cmsg $_stat_print\033[0m" >/dev/tty 2>/dev/null || true
    fi
  fi
  _TURN_STAGED_FILES=""
}

# ─── Agent Loop (one user turn → multi-turn tool use → final answer) ────────
run_agent() {
  local input="$1"
  local _t_start; _t_start=$(_mix_date_nano)
  _TURN_STAGED_FILES=""
  compact_history  # auto-compact before adding new turn
  append_text "user" "$input"
  _TOOLS_USED=0

  # Plan mode: generate and show numbered plan, ask approval before tools
  if [ "$AGENT_MODE" = "plan" ]; then
    printf "\r\033[K  \033[1;35m$I_PLAN planning...\033[0m"
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
  local _tool_streak=0        # consecutive same-tool calls
  local _last_tool_name=""    # for streak detection
  local _warned_streak=false  # only inject hint once
  # Show context bar before first turn so user sees budget early
  ctx_bar
  while [ "$turn" -lt "$MAX_TURNS" ]; do
    turn=$((turn + 1))

    # ── High-turn warning ──
    if [ "$turn" -eq 20 ]; then
      echo -e "  \033[1;33m⚠ High turn count (20+). Consider breaking task into smaller steps.\033[0m" >/dev/tty 2>/dev/null || true
    fi
    # Compact mid-loop: after tool results appended, before next API call
    # Skip turn 1 (already compacted above). Check every turn — cheap count
    # gate inside compact_history means real compact only fires at MAX_HIST_MSGS.
    [ "$turn" -gt 1 ] && compact_history

    # Show pre-process latency on first turn before starting spinner
    if [ "$turn" -eq 1 ] && [ "$_t_start" -gt 0 ]; then
      local _t_now; _t_now=$(_mix_date_nano)
      if [ "$_t_now" -gt 0 ]; then
        local _pp_ms=$(( (_t_now - _t_start) / 1000000 ))
        [ "$_pp_ms" -gt 50 ] && echo -e "  \033[0;90m  pre-process: ${_pp_ms}ms\033[0m" >/dev/tty 2>/dev/null || true
      fi
    fi

    # Always start animated spinner (Python will kill it before streaming first token)
    start_spinner "mix (turn $turn)"
    export SPIN_PID="$_SPIN_PID"
    tmux_update   # show ⟳ in tmux status while thinking

    local parsed
    local _api_attempt _api_max_retries=3
    for _api_attempt in 1 2 3; do
      if [ "$STREAM" = "true" ]; then
        parsed=$(call_api_stream)
        _SESSION_API_CALLS=$((_SESSION_API_CALLS + 1))
        local _usage_line _pt _ct _cache
        _usage_line=$(printf '%s' "$parsed" | grep '^USAGE:' | head -1 || true)
        if [ -n "$_usage_line" ]; then
          _pt=${_usage_line#USAGE:}; _pt=${_pt%%:*}
          local _rest=${_usage_line#USAGE:}; _rest=${_rest#*:}
          _ct=${_rest%%:*}
          # Third field = cache tokens (only if present)
          case "$_rest" in
            *:*) _cache=${_rest#*:} ;;
            *) _cache=0 ;;
          esac
          _SESSION_PROMPT_TOKENS=$((_SESSION_PROMPT_TOKENS + _pt))
          _SESSION_COMPLETION_TOKENS=$((_SESSION_COMPLETION_TOKENS + _ct))
          _SESSION_CACHE_TOKENS=$((_SESSION_CACHE_TOKENS + _cache))
        fi
        if [[ "$parsed" == FAIL:* ]]; then
          if [[ "$parsed" == "FAIL:interrupted" ]]; then
            stop_spinner
            echo -e "\r\033[K  \033[1;31m(Turn Cancelled)\033[0m" >/dev/tty 2>/dev/null || true
            break 2
          fi
          [ "$INTERACTIVE" = false ] \
            && echo -e "    \033[0;90m↻ API error '${parsed#FAIL:}' (attempt $_api_attempt/$_api_max_retries) — retrying without streaming...\033[0m" >&2 \
            || echo -e "    \033[0;90m↻ API error '${parsed#FAIL:}' (attempt $_api_attempt/$_api_max_retries) — retrying without streaming...\033[0m" >/dev/tty 2>/dev/null
          start_spinner "turn $turn (retry $_api_attempt)"
          local resp; resp=$(call_api)
          if [[ "$resp" == FAIL:* ]]; then
            if [[ "$resp" == "FAIL:interrupted" ]]; then
              stop_spinner
              echo -e "\r\033[K  \033[1;31m(Turn Cancelled)\033[0m" >/dev/tty 2>/dev/null || true
              break 2
            fi
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
          if [[ "$resp" == "FAIL:interrupted" ]]; then
            stop_spinner
            echo -e "\r\033[K  \033[1;31m(Turn Cancelled)\033[0m" >/dev/tty 2>/dev/null || true
            break 2
          fi
          stop_spinner
          if [ "$_api_attempt" -lt "$_api_max_retries" ]; then
            echo -e "\r\033[K  \033[0;90m↻ API error (attempt $_api_attempt/$_api_max_retries), retrying...\033[0m"
            start_spinner "turn $turn (retry $_api_attempt)"
            continue
          fi
          echo -e "\r\033[K  \033[1;31mAPI failed after $_api_max_retries attempts: ${resp#FAIL:}\033[0m"
          break 2
        fi
        # Track token usage from API response
        _SESSION_API_CALLS=$((_SESSION_API_CALLS + 1))
        local _pt _ct _cache
        _pt=$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("usage",{}).get("prompt_tokens",0))' 2>/dev/null) || _pt=0
        _ct=$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("usage",{}).get("completion_tokens",0))' 2>/dev/null) || _ct=0
        _cache=$(printf '%s' "$resp" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("usage",{}).get("prompt_tokens_details",{}).get("cached_tokens",0))' 2>/dev/null) || _cache=0
        _SESSION_PROMPT_TOKENS=$((_SESSION_PROMPT_TOKENS + _pt))
        _SESSION_COMPLETION_TOKENS=$((_SESSION_COMPLETION_TOKENS + _ct))
        _SESSION_CACHE_TOKENS=$((_SESSION_CACHE_TOKENS + _cache))
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
    raw_msg=$(printf '%s' "$raw_b64" | _mix_base64_decode) || raw_msg='{"role":"assistant","content":""}'
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

      local _batch_dir; _batch_dir=$(mktemp -d -t mix-$$-batch-XXXXXX)
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
          echo -e "    \033[38;5;99m$I_TOOL\033[0m \033[1;36m$_tname\033[0m \033[0;90m(parallel)\033[0m"
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

      # ── Streak detection: break loops of repeated same-tool calls ──
      # Track the tool names used this turn
      local _turn_tools=""
      for _pref in "${_parallel_refs[@]}"; do _turn_tools+=" ${_pref##*|}"; done
      for tc in "${_sequential_tcs[@]}"; do
        local _rest="${tc#TC:}"; _rest="${_rest#*|||}"; _rest="${_rest%%|||*}"
        _turn_tools+=" $_rest"
      done
      if [ -n "$_turn_tools" ]; then
        # Check if all tools this turn match the previous turn's tool
        local _all_same=true
        for _tn in $_turn_tools; do
          [ "$_tn" != "$_last_tool_name" ] && _all_same=false
        done
        if [ "$_all_same" = true ] && [ -n "$_last_tool_name" ]; then
          _tool_streak=$((_tool_streak + 1))
        else
          _tool_streak=1
          _last_tool_name="${_turn_tools## }"
          _last_tool_name="${_last_tool_name%% *}"
        fi
        # Inject a course-correction hint after 5 consecutive same-tool calls
        if [ "$_tool_streak" -ge 5 ] && [ "$_warned_streak" = false ]; then
          _warned_streak=true
          echo -e "  \033[1;33m⚠ Tool loop detected: $_last_tool_name called $_tool_streak times in a row.\033[0m" >/dev/tty 2>/dev/null || true
          echo -e "  \033[0;90m  Injecting hint: try read_file instead of repeated searches, or provide your final answer.\033[0m" >/dev/tty 2>/dev/null || true
          # Inject a hint message into history so the model sees it
          append_raw_nosave '{"role":"user","content":"[SYSTEM HINT] You have called '"$_last_tool_name"' '"$_tool_streak"' times in a row with similar queries. This is a loop. Switch to read_file to get the full file content, or provide your final answer now. Do NOT call '"$_last_tool_name"' again with a slightly different query."}'
          save_history
        fi
      fi

      # Turn progress indicator — shows where we are in the agent loop
      echo -e "    \033[0;90m⤷ turn $turn · $_TOOLS_USED tools · ~$(_fmt_tok $((_SESSION_PROMPT_TOKENS + _SESSION_COMPLETION_TOKENS))) tokens\033[0m"
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
  
  _commit_turn "$input"

  ctx_bar       # show context window usage after every agent turn
  tmux_update   # refresh tmux status bar

  # Proactive memory: auto-log lessons learned
  proactive_memory "$input" "$_TOOLS_USED"
}

