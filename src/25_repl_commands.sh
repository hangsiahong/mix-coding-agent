# ─── REPL Commands ──────────────────────────────────────────────────────────
handle_cmd() {
  # Extensions get first crack at commands
  _ext_dispatch_cmd "$1" && return 0

  case "$1" in
    /paste)
      local dir="/tmp/mix-clipboard"
      mkdir -p "$dir"
      local txt=""
      if command -v wl-paste >/dev/null 2>&1; then
        txt=$(wl-paste -t text/plain 2>/dev/null)
      elif command -v xclip >/dev/null 2>&1; then
        txt=$(xclip -selection clipboard -o 2>/dev/null)
      elif command -v pbpaste >/dev/null 2>&1; then
        txt=$(pbpaste 2>/dev/null)
      fi
      if [ -n "$txt" ]; then
        local pid=$(date +%s%N)
        printf '%s' "$txt" > "$dir/txt_$pid.txt"
        local lines=$(printf '%s\n' "$txt" | wc -l)
        INPUT="[paste _$pid: $lines lines]"
        echo -e "  \033[38;5;99m✓\033[0m Paste appended context (${lines} lines)"
        return 1 # Return 1 to tell loop to fall through and process INPUT
      else
        echo "  Clipboard is empty or missing xclip/wl-paste/pbpaste"
      fi
      ;;
    /flush)  HISTORY='[]'; rm -f "$HIST_FILE"; session_clear; echo "  History + session cleared." ;;
    /resume)
      if [ "$_SESSION_AVAILABLE" = true ]; then
        session_apply
      else
        echo "  No saved session to restore."
      fi
      ;;
    /undo)
      if [ "$GIT_ENABLED" != true ]; then
        echo "  /undo requires git (GIT_ENABLED=true)"
      else
        local _last_rev; _last_rev=$(git -C "$WORKDIR" --no-pager log --oneline -1 2>/dev/null) || true
        if [ -z "$_last_rev" ]; then
          echo "  No commits to undo."
        else
          echo "  Last commit: $_last_rev"
          git -C "$WORKDIR" --no-pager diff HEAD~1 --stat 2>/dev/null | head -10
          if confirm "  Revert this commit? [y/N] "; then
            git -C "$WORKDIR" revert --no-edit HEAD 2>/dev/null \
              && echo -e "  \033[38;5;82m✓ Reverted\033[0m" \
              || echo -e "  \033[1;31m✗ Revert failed (merge conflict?)\033[0m"
          fi
        fi
      fi
      ;;
    /stash)
      if [ "$GIT_ENABLED" != true ]; then
        echo "  /stash requires git"
      else
        local _stash_out; _stash_out=$(git -C "$WORKDIR" stash 2>&1) || true
        echo "  $_stash_out"
      fi
      ;;
    /stats)
      local _total_tok=$(( (_SESSION_PROMPT_TOKENS + _SESSION_COMPLETION_TOKENS) ))
      echo -e "  \033[1;37mSession Stats\033[0m"
      echo "  API calls:     $_SESSION_API_CALLS"
      echo "  Prompt tokens:  $_SESSION_PROMPT_TOKENS"
      echo "  Output tokens:  $_SESSION_COMPLETION_TOKENS"
      echo "  Total tokens:   $_total_tok"
      echo "  Tools used:     $_TOOLS_USED"
      local _hist_n; _hist_n=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || _hist_n="?"
      echo "  History msgs:   $_hist_n"
      ;;
    /refresh) repo_map_invalidate; echo -e "  \033[38;5;82m✓\033[0m Repo map invalidated. Will rebuild on next API call." ;;
    /cache)
      local _nc
      _nc=$(printf '%s' "$_FILE_CACHE" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || _nc=0
      if [ "$_nc" -eq 0 ]; then
        echo "  File cache: empty (files auto-cache on read_file)"
      else
        echo -e "  \033[1;32mFile cache:\033[0m $_nc files"
        for _fp in $_FILE_CACHE_ORDER; do
          local _sz
          _sz=$(printf '%s' "$_FILE_CACHE" | python3 -c "import json,sys;c=json.load(sys.stdin).get('$_fp',{});print(c.get('lines','?'))" 2>/dev/null) || _sz="?"
          echo -e "    \033[0;90m$_fp ($_sz lines)\033[0m"
        done
        echo "  Survives history compaction. Invalidation: /cache clear"
      fi
      ;;
    /cache\ clear)
      _FILE_CACHE='{}'; _FILE_CACHE_ORDER=""
      echo -e "  \033[38;5;82m✓\033[0m File cache cleared."
      ;;
    /verify)
      echo "  Auto-verify: $AUTO_VERIFY"
      echo "  Usage: /verify [on|off]  — toggle syntax/lint/typecheck after edits"
      ;;
    /verify\ on)
      AUTO_VERIFY="on"
      echo -e "  \033[38;5;82m✓\033[0m Auto-verify ON — will run checks after edit_file/create_file"
      ;;
    /verify\ off)
      AUTO_VERIFY="off"
      echo -e "  \033[0;90m  Auto-verify OFF\033[0m"
      ;;
    /verify\ *)
      local _varg="${1#/verify }"
      case "$_varg" in
        on|off) AUTO_VERIFY="$_varg"; echo "  Auto-verify → $AUTO_VERIFY" ;;
        *) echo "  Unknown. Use: /verify [on|off]" ;;
      esac
      ;;
    /models)
      if type "${PROVIDER}_list_models" >/dev/null 2>&1; then
        ${PROVIDER}_list_models
      else
        echo "  Provider '$PROVIDER' has no models list."
        echo "  Use /model <id> to set manually."
      fi
      ;;
    /model)  echo "  Model: $MODEL | Provider: $PROVIDER | URL: $BASE_URL" ;;
    /model\ *)
      local _new_model="${1#/model }"
      # Validate against provider if it supports it
      if [ "$PROVIDER" != "default" ] && type "${PROVIDER}_validate_model" >/dev/null 2>&1; then
        local _vout; _vout=$(${PROVIDER}_validate_model "$_new_model" 2>/dev/null)
        local _vcode=$?
        if [ $_vcode -ne 0 ]; then
          echo "  ✗ Model '$_new_model' not available on provider '$PROVIDER'"
          [ -n "$_vout" ] && echo "  $_vout"
          echo "  Use /models to list available models."
          return 0
        fi
      fi
      MODEL="$_new_model"
      echo "  Model → $MODEL"
      _mix_save_defaults
      ;;
    /provider)
      echo "  Provider: $PROVIDER"
      echo "  Base URL: $BASE_URL"
      echo "  Model: $MODEL"
      echo ""
      echo "  Available providers:"
      local _plist; _plist=$(_list_providers 2>/dev/null)
      if [ -n "$_plist" ]; then
        while IFS= read -r _pn; do
          echo "    - $_pn"
        done <<< "$_plist"
      else
        echo "    (none found)"
      fi
      echo "  User providers: drop .sh in ~/.mix/providers/"
      echo ""
      echo "  Usage: /provider <name>        (activate provider)"
      echo "         /provider <name> login   (run provider OAuth/login)"
      echo "         /provider <name> models  (list available models)"
      echo "         /provider default        (reset to default)"
      ;;
    /provider\ default)
      PROVIDER="default"
      BASE_URL="https://ai.koompi.cloud/v1"
      if [ -f "${HOME}/.mix/api_key" ]; then API_KEY=$(cat "${HOME}/.mix/api_key"); fi
      MODEL="${AGENT_MODEL:-glm-5}"
      echo "  Provider → default (koompi proxy)"
      _mix_save_defaults
      ;;
    /provider\ *)
      local _pargs="${1#/provider }"
      local _pname="${_pargs%% *}"
      local _paction="${_pargs#* }"
      [ "$_paction" = "$_pname" ] && _paction=""

      if [ "$_pname" = "default" ]; then
        PROVIDER="default"
        BASE_URL="https://ai.koompi.cloud/v1"
        if [ -f "${HOME}/.mix/api_key" ]; then API_KEY=$(cat "${HOME}/.mix/api_key"); fi
        MODEL="${AGENT_MODEL:-glm-5}"
        echo "  Provider → default (koompi proxy)"
      elif _load_provider "$_pname"; then
        case "$_paction" in
          "")
            # Activate
            if type "${_pname}_activate" >/dev/null 2>&1; then
              ${_pname}_activate && _mix_save_defaults
            else
              echo "  Provider $_pname loaded (no _activate hook found)"
              echo "  Set BASE_URL, API_KEY, MODEL manually or define ${_pname}_activate()"
            fi
            ;;
          login)
            if type "${_pname}_login" >/dev/null 2>&1; then
              ${_pname}_login
            else
              echo "  Provider $_pname has no login flow."
            fi
            ;;
          models)
            if type "${_pname}_list_models" >/dev/null 2>&1; then
              ${_pname}_list_models
            else
              echo "  Provider $_pname has no models command."
            fi
            ;;
          *)
            echo "  Unknown action: $_paction"
            echo "  Available: login, models, (empty=activate)"
            ;;
        esac
      else
        echo "  Provider not found: $_pname"
        echo "  Checked: $PROVIDER_DIR/${_pname}.sh, $MIX_PROVIDERS_DIR/${_pname}.sh"
      fi
      ;;
    /history)
      local n; n=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || n="?"
      echo "  $n messages in history"
      ;;
    /caveman)
      echo "  Caveman mode: $CAVEMAN_MODE"
      echo "  Usage: /caveman [off|lite|full|ultra]"
      ;;
    /caveman\ *)
      local mode="${1#/caveman }"
      case "$mode" in
        off|lite|full|ultra)
          CAVEMAN_MODE="$mode"
          echo "  Caveman → $CAVEMAN_MODE"
          ;;
        *) echo "  Unknown mode: $mode. Use: off lite full ultra" ;;
      esac
      ;;
    /mode)
      echo "  Mode: $AGENT_MODE  (fast=just act | deep=reason-first | plan=show-plan+approve)"
      ;;
    /mode\ *)
      local _m="${1#/mode }"
      case "$_m" in
        fast|deep|plan) AGENT_MODE="$_m"; echo "  Mode → $AGENT_MODE" ;;
        *) echo "  Unknown. Use: fast deep plan" ;;
      esac
      ;;
    /ext)
      if [ -z "$_MIX_EXTENSIONS_LOADED" ]; then
        echo -e "  \033[0;90mNo extensions loaded.\033[0m"
        echo "  Usage: /ext load <name>   /ext unload <name>   /ext create <name>   /ext reload   /ext list"
        echo "  Drop .sh files in ~/.mix/extensions/ or .mix/extensions/"
      else
        echo -e "  \033[1;37mExtensions:\033[0m"
        _ext_list
      fi
      ;;
    /ext\ load\ *)
      local _ename="${1#/ext load }"
      _ext_load_one "$_ename"
      ;;
    /ext\ unload\ *)
      local _ename="${1#/ext unload }"
      _ext_unload "$_ename"
      ;;
    /ext\ create\ *)
      local _ename="${1#/ext create }"
      _ext_create "$_ename"
      ;;
    /ext\ reload)
      _ext_reload
      ;;
    /ext\ list)
      _ext_list
      ;;
    /help)
      echo "  cavekit: /spec [idea|bug:|amend|from-code]  /build [§T.n|--next|--all]  /check [§V|§I|§T|--all]"
      echo "  testing: /test [init|generate|run|coverage]  — /test init to scaffold from scratch"
      echo "  agent:   /flush  /undo  /stash  /stats  /compact  /refresh  /resume  /cache [clear]  /verify [on|off]  /model [id]  /models  /provider [name]  /history  /caveman [off|lite|full|ultra]  /mode [fast|deep|plan]  /yolo  /config  /ext [load|unload|create|reload|list]  /workers  /worker <name> <cmd>  /subagent <name> <task>  /afk [hint]  /afk log  /afk stop  /afk setup  /afk apply  /skill <name>  /skills  /help  /exit"
      ;;
    /skills)
      if [ -z "$ACTIVE_SKILLS" ]; then
        echo -e "  \033[0;90mNo active skills.\033[0m"
        echo -e "  Available in ~/.mix/skills/:"
        for f in "$HOME/.mix/skills/"*.md; do
          [ -f "$f" ] && echo -e "    - \033[1;34m$(basename "$f" .md)\033[0m"
        done
      else
        echo -e "  \033[1;32m● Active Skills:\033[0m"
        for s in $ACTIVE_SKILLS; do
          echo -e "    - \033[1;34m$(basename "$s" .md)\033[0m \033[0;90m($s)\033[0m"
        done
      fi
      ;;
    /skill\ clear)
      ACTIVE_SKILLS=""
      echo "  Skills cleared."
      ;;
    /skill)
      echo "  Available skills:"
      local count=0
      for f in .mix/skills/*.md "$HOME/.mix/skills/"*.md; do
        if [ -f "$f" ]; then
          echo "    - $(basename "$f" .md)"
          count=$((count + 1))
        fi
      done
      if [ "$count" -eq 0 ]; then
        echo "    (No skills found in .mix/skills or ~/.mix/skills)"
      fi
      echo "  Usage: /skill <name>   (loads a skill)"
      echo "         /skills         (lists active skills)"
      echo "         /skill clear    (clears active skills)"
      ;;
    /skill\ *)
      local _sk="${1#/skill }"
      local _found=""
      if [ -f "$_sk" ]; then _found="$_sk"
      elif [ -f ".mix/skills/$_sk.md" ]; then _found=".mix/skills/$_sk.md"
      elif [ -f ".mix/skills/$_sk" ]; then _found=".mix/skills/$_sk"
      elif [ -f "$HOME/.mix/skills/$_sk.md" ]; then _found="$HOME/.mix/skills/$_sk.md"
      elif [ -f "$HOME/.mix/skills/$_sk" ]; then _found="$HOME/.mix/skills/$_sk"
      fi
      if [ -n "$_found" ]; then
        if echo "$ACTIVE_SKILLS" | grep -qF "$_found"; then
          echo "  Skill already loaded: $_found"
        else
          ACTIVE_SKILLS="$ACTIVE_SKILLS $_found"
          ACTIVE_SKILLS="${ACTIVE_SKILLS# }"
          echo "  Skill loaded: $_found"
        fi
      else
        echo "  Skill not found: $_sk / $_sk.md (checked ., .mix/skills/, ~/.mix/skills/)"
      fi
      ;;
    /compact)
      local _cmsg_before
      _cmsg_before=$(printf '%s' "$HISTORY" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || _cmsg_before="0"
      if [ "$_cmsg_before" -lt 4 ] 2>/dev/null; then
        echo "  History too short to compact ($_cmsg_before msgs)."
      else
        local _saved="$MAX_HIST_MSGS"; MAX_HIST_MSGS=0; compact_history; MAX_HIST_MSGS="$_saved"
      fi
      ;;
    /yolo)
      if [ "$AUTO_YES" = "true" ]; then
        AUTO_YES=false; echo "  Yolo mode OFF — will prompt before each command."
      else
        AUTO_YES=true;  echo "  Yolo mode ON  — auto-confirming commands (guardrails active)."
      fi
      ;;
    /config)
      echo -e "  \033[1;37mActive Config\033[0m"
      echo "  Model:        $MODEL"
      echo "  Provider:     $PROVIDER"
      echo "  Base URL:     $BASE_URL"
      echo "  Caveman:      $CAVEMAN_MODE"
      echo "  Agent Mode:   $AGENT_MODE"
      echo "  Auto-verify:  ${AUTO_VERIFY:-off}"
      echo "  Stream:       $STREAM"
      echo "  Yolo:         $AUTO_YES"
      echo "  Max Turns:    $MAX_TURNS"
      echo "  Max Hist:     $MAX_HIST_MSGS"
      echo "  Context:      $CTX_TOKENS tokens"
      echo "  Git:          $GIT_ENABLED"
      echo "  Workdir:      $WORKDIR"
      if [ -n "${VERIFY_CMD:-}" ]; then echo "  Verify Cmd:   $VERIFY_CMD"; fi
      if [ -n "${TEST_CMD:-}" ]; then echo "  Test Cmd:     $TEST_CMD"; fi
      echo ""
      _mixrc_show
      ;;
    /undo)
      if [ "$GIT_ENABLED" = true ]; then
        if git rev-parse HEAD~1 >/dev/null 2>&1; then
          git reset --soft HEAD~1
          echo "  Undo successful: git reset --soft HEAD~1"
        else
          echo "  Git undo failed: no previous commit found."
        fi
      else
        echo "  Undo failed: git is not enabled or not a repository."
      fi
      ;;
    /exit)   echo "  Bye!"; # clean up tmux worker windows on exit if desired
             exit 0 ;;
    /workers)
      if [ -z "$TMUX" ]; then
        echo "  Not in tmux."
      else
        echo "  Windows in this session:"
        tmux list-windows -F '    #I: #W  (#F)' 2>/dev/null || echo "  (none)"
      fi
      ;;
    /worker\ *)
      local _wargs="${1#/worker }"
      local _wname="${_wargs%% *}"
      local _wcmd="${_wargs#* }"
      if [ -z "$TMUX" ]; then
        echo "  Not in tmux — can't spawn worker."
      elif [ -z "$_wname" ] || [ "$_wname" = "$_wargs" ]; then
        echo "  Usage: /worker <name> <command>"
      else
        tmux new-window -n "$_wname" "bash -c '$_wcmd; read -p done' " 2>/dev/null \
          && echo "  ↳ worker [$_wname] spawned" \
          || echo "  Failed to spawn worker."
      fi
      ;;
    /subagent\ *)
      local _sargs="${1#/subagent }"
      local _sname="${_sargs%% *}"
      local _stask="${_sargs#* }"
      if [ -z "$TMUX" ]; then
        echo "  Not in tmux — can't spawn subagent."
      elif [ -z "$_sname" ] || [ "$_sname" = "$_sargs" ]; then
        echo "  Usage: /subagent <name> <task>"
      else
        # Write task to a temp file to avoid quote escaping issues when passing to tmux
        local _stmp _mytty
        _stmp=$(mktemp -t mix-XXXXXX)
        _mytty=$(tty)
        printf '%s\n' "$_stask" > "$_stmp"
        tmux new-window -n "$_sname" "bash -c 'cat $_stmp | mix 2>&1 | tee /tmp/${_sname}.log; rm -f $_stmp; echo -e \"\n  \033[38;5;82m✓ Subagent [$_sname] finished!\033[0m (Ask mix to read /tmp/${_sname}.log)\" > $_mytty; echo \"\"; echo \"[Subagent finished. Press Enter to close]\"; read -r'" 2>/dev/null \
          && echo "  ↳ subagent [$_sname] spawned logging to /tmp/${_sname}.log" \
          || echo "  Failed to spawn subagent."
      fi
      ;;
    /afk\ setup)
      telegram_setup
      ;;
    /afk\ status|/afk\ log)
      local _plan="${HOME}/.mix/afk-plan.md"
      if [ -f "$_plan" ]; then
        echo "  ── ~/.mix/afk-plan.md ──"
        cat "$_plan"
      else
        echo "  No plan yet. Run /afk to generate one."
      fi
      ;;
    /afk\ stop)
      if [ -n "${MIX_AFK_WIN:-}" ] && [ -n "$TMUX" ]; then
        tmux kill-window -t "$MIX_AFK_WIN" 2>/dev/null && echo "  AFK worker stopped." || echo "  AFK window not found."
        MIX_AFK_WIN=""
      else
        echo "  No tracked AFK window (kill manually: tmux kill-window -t mix-afk)"
      fi
      ;;
    /afk\ apply)
      local _plan_save="${HOME}/.mix/afk-plan.md"
      if [ ! -f "$_plan_save" ]; then
        echo "  No saved plan found at $_plan_save"
        echo "  Run /afk first to generate a plan."
        return 0
      fi
      echo "  Applying saved plan from $_plan_save"
      echo "  ── Plan ──"
      cat "$_plan_save"
      echo "  ──────────"
      printf '  Apply this plan now? [y/N] '
      local _yn; read -r _yn < /dev/tty
      if [[ "$_yn" =~ ^[Yy]$ ]]; then
        local _apply_prompt
        _apply_prompt="[AFK APPLY MODE] The user reviewed and approved this plan. Execute each item using edit_file and bash. For each: read the file first, make the minimal targeted edit, be conservative. Do not change anything not in the plan.

Plan to execute:
$(cat "$_plan_save")"
        run_agent "$_apply_prompt"
      else
        echo "  Aborted."
      fi
      ;;
    /afk*)
      local _afk_hint="${1#/afk}"; _afk_hint="${_afk_hint# }"

      if [ -z "$TMUX" ]; then
        echo "  Not in tmux — AFK requires tmux for background execution."
        return 0
      fi

      # Decide mode: Telegram or plan-file-only
      local _use_tg=false
      if telegram_is_configured 2>/dev/null; then
        _use_tg=true
      fi

      local _plan_save="${HOME}/.mix/afk-plan.md"
      local _apply_tmp; _apply_tmp=$(mktemp -t mix-afk-apply-XXXXXX)
      local _prompt_tmp; _prompt_tmp=$(mktemp -t mix-afk-prompt-XXXXXX)
      local _worker_tmp; _worker_tmp=$(mktemp -t mix-afk-worker-XXXXXX)

      if [ -n "$_afk_hint" ]; then
        # Custom prompt mode: user provided a task/direction
        cat > "$_prompt_tmp" << PLAN_PROMPT_END
[AFK PLAN MODE] The user is away. Follow this task, then write your plan as a markdown file to: ${_plan_save}

User task: ${_afk_hint}

Rules:
- Do NOT use edit_file or bash commands with side effects
- Read-only bash only: cat, grep, git log, git status, git diff, find, wc
- Analyse what's needed, then write a concrete plan
- Use the bash tool to write the plan file at the end

At the end, run this bash command to save your plan (replace the content):
\`\`\`bash
cat > ${_plan_save} << 'EOF'
# AFK Plan — \$(date '+%Y-%m-%d %H:%M')

Task: ${_afk_hint}

[your plan items here, one per line]
EOF
\`\`\`

Keep the plan concise: each item should be one line with a risk level (low/med/high).
PLAN_PROMPT_END
      else
        # Default mode: analyse codebase for issues
        cat > "$_prompt_tmp" << PLAN_PROMPT_END
[AFK PLAN MODE] The user is away. Analyse the codebase, then write your plan as a markdown file to: ${_plan_save}

Rules:
- Do NOT use edit_file or bash commands with side effects
- Read-only bash only: cat, grep, git log, git status, git diff, find, wc
- Use the bash tool to write the plan file at the end

Analysis to perform:
1. grep for TODO/FIXME/HACK/BUG in src/ — list file:line for each
2. git log --oneline -15 and look for obvious logic bugs or unquoted shell vars
3. Check for injection risks (eval with unquoted vars, etc.)
4. Check README.md accuracy

At the end, run this bash command to save your plan (replace the content):
\`\`\`bash
cat > ${_plan_save} << 'EOF'
# AFK Plan — \$(date '+%Y-%m-%d %H:%M')

[your plan items here, one per line]
EOF
\`\`\`

Keep the plan concise: each item should be one line with a risk level (low/med/high).
PLAN_PROMPT_END
      fi

      cat > "$_apply_tmp" << 'APPLY_PREFIX_END'
[AFK APPLY MODE] The user reviewed and approved this plan via Telegram. Execute each item using edit_file and bash. Read each file before editing. Make minimal targeted changes. Do not touch anything outside the plan scope.

Plan to execute:
APPLY_PREFIX_END

      # Worker: run mix with plan prompt, then read the written file and send to Telegram
      cat > "$_worker_tmp" << 'AFK_WORKER_END'
#!/usr/bin/env bash
PROMPT_FILE="$1"
APPLY_PREFIX_FILE="$2"
PLAN_SAVE="$3"
WORKDIR="$4"
MY_TTY="$5"
USE_TG="$6"
cd "$WORKDIR" || exit 1

TG_CONFIG="$HOME/.mix/telegram"
TG_TOKEN=$(grep '^BOT_TOKEN=' "$TG_CONFIG" 2>/dev/null | cut -d= -f2- || true)
TG_CHAT=$(grep '^CHAT_ID='   "$TG_CONFIG" 2>/dev/null | cut -d= -f2- || true)

MIX_BIN=""
for _try in "$HOME/.local/bin/mix" "$HOME/bin/mix" "$(command -v mix 2>/dev/null || true)"; do
    [ -x "$_try" ] && MIX_BIN="$_try" && break
done
[ -z "$MIX_BIN" ] && { echo "ERROR: mix not found"; exit 1; }

tg_send() {
    [ "$USE_TG" != "true" ] && return 0
    python3 - "$1" "$TG_TOKEN" "$TG_CHAT" << 'PYEOF'
import sys, json, urllib.request
payload = json.dumps({'chat_id': sys.argv[3], 'text': sys.argv[1], 'parse_mode': 'Markdown'}).encode()
req = urllib.request.Request(f'https://api.telegram.org/bot{sys.argv[2]}/sendMessage',
    data=payload, headers={'Content-Type': 'application/json'})
try: urllib.request.urlopen(req, timeout=10)
except: pass
PYEOF
}

tg_send_buttons() {
    [ "$USE_TG" != "true" ] && return 0
    python3 - "$1" "$TG_TOKEN" "$TG_CHAT" << 'PYEOF'
import sys, json, urllib.request
payload = json.dumps({'chat_id': sys.argv[3], 'text': sys.argv[1], 'parse_mode': 'Markdown',
    'reply_markup': {'inline_keyboard': [[
        {'text': '✅ Apply', 'callback_data': 'afk_yes'},
        {'text': '❌ Skip',  'callback_data': 'afk_no'}
    ]]}}).encode()
req = urllib.request.Request(f'https://api.telegram.org/bot{sys.argv[2]}/sendMessage',
    data=payload, headers={'Content-Type': 'application/json'})
try: urllib.request.urlopen(req, timeout=10)
except: pass
PYEOF
}

tg_poll() {
    local deadline=$(( $(date +%s) + ${1:-7200} ))
    local offset=0
    local init; init=$(curl -s --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?limit=1&offset=-1" 2>/dev/null || echo '{"result":[]}')
    offset=$(python3 -c "import json,sys; r=json.loads(sys.argv[1]).get('result',[]); print(r[-1].get('update_id',0)+1 if r else 0)" "$init" 2>/dev/null || echo 0)
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local resp; resp=$(curl -s --max-time 35 "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=${offset}&timeout=30&allowed_updates=%5B%22callback_query%22%5D" 2>/dev/null) || { sleep 5; continue; }
        local hit; hit=$(python3 -c "
import json,sys
try:
    for u in json.loads(sys.argv[1]).get('result',[]):
        cb=u.get('callback_query',{})
        d=cb.get('data','')
        if d in ('afk_yes','afk_no'):
            print(str(u['update_id']+1)+':'+cb.get('id','')+':'+d); break
except: pass
" "$resp" 2>/dev/null || true)
        if [ -n "$hit" ]; then
            local cb_id="${hit#*:}"; cb_id="${cb_id%%:*}"
            [ -n "$cb_id" ] && curl -s --max-time 5 -X POST "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" -d "callback_query_id=${cb_id}" >/dev/null 2>&1 || true
            printf '%s' "${hit##*:afk_}"; return 0
        fi
    done
    printf 'timeout'
}

PROJECT="$(basename "$WORKDIR")"
tg_send "🤖 *mix AFK started*
📁 \`${PROJECT}\`  🕐 $(date '+%H:%M %Z')
_Analysing codebase..._"

# Run mix — it will write the plan to $PLAN_SAVE via bash tool
echo "  Analysing..."
mkdir -p "$(dirname "$PLAN_SAVE")"
"$MIX_BIN" < "$PROMPT_FILE"

# Read whatever the agent wrote
if [ -s "$PLAN_SAVE" ]; then
    PLAN=$(cat "$PLAN_SAVE")
else
    PLAN="(Agent did not write a plan file — run /afk manually to debug)"
    printf '%s\n' "$PLAN" > "$PLAN_SAVE"
fi

echo ""
echo "  ── Plan saved to $PLAN_SAVE ──"

if [ "$USE_TG" = "true" ]; then
    MSG="🗒 *AFK Plan — ${PROJECT}*

${PLAN:0:3500}
$([ ${#PLAN} -gt 3500 ] && echo '..._(truncated)_' || true)

---
_✅ Apply  or  ❌ Skip_"
    tg_send_buttons "$MSG"
    tg_send "⏳ _Waiting up to 2h for your decision..._"

    REPLY=$(tg_poll 7200)
    case "$REPLY" in
        yes)
            tg_send "✅ *Approved — applying now...*"
            APPLY_PROMPT="$(cat "$APPLY_PREFIX_FILE")
$PLAN"
            MIX_YOLO=1 "$MIX_BIN" <<< "$APPLY_PROMPT"
            tg_send "✅ *Done!* Back at keyboard? Run \`/afk log\` in mix."
            ;;
        no)
            tg_send "❌ *Skipped.* Run \`/afk apply\` in mix when ready."
            ;;
        timeout)
            tg_send "⏰ *2h timeout.* Run \`/afk apply\` in mix when ready."
            ;;
    esac
else
    echo "  (No Telegram — run /afk apply to execute the plan)"
fi

[ -n "$MY_TTY" ] && printf '\n  \033[38;5;82m✓ AFK done!\033[0m\n' > "$MY_TTY" 2>/dev/null || true
echo ""; echo "[AFK finished. Press Enter]"; read -r _
AFK_WORKER_END
      chmod +x "$_worker_tmp"

      local _mytty; _mytty=$(tty 2>/dev/null || echo "")
      tmux new-window -n "mix-afk" \
        "bash '$_worker_tmp' '$_prompt_tmp' '$_apply_tmp' '$_plan_save' '$PWD' '$_mytty' '$_use_tg'; rm -f '$_prompt_tmp' '$_apply_tmp' '$_worker_tmp'" \
        2>/dev/null
      if [ $? -eq 0 ]; then
        MIX_AFK_WIN="mix-afk"
        printf '  \033[38;5;99m🌙 AFK mode active\033[0m — working in background\n'
        if [ "$_use_tg" = "true" ]; then
          printf '  Telegram: plan will be sent for approval\n'
        else
          printf '  \033[38;5;220m⚠ No Telegram configured.\033[0m Run \033[1m/afk setup\033[0m to enable phone approval.\n'
          printf '  Plan will be saved to %s — run /afk apply to execute.\n' "$_plan_save"
        fi
        printf '  Check back: /afk log   Stop: /afk stop\n'
      else
        echo "  Failed to spawn AFK worker."
        rm -f "$_prompt_tmp" "$_apply_tmp" "$_worker_tmp"
      fi
      ;;
    /spec*)
      local _sa="${1#/spec}"; _sa="${_sa# }"
      local _si
      if [ ! -f "$WORKDIR/SPEC.md" ]; then
        _si="[/spec NEW] Create SPEC.md at $WORKDIR/SPEC.md. Idea: $_sa
Steps: 1. §G: goal 1 line caveman. 2. §C: constraints bullets. 3. §I: external surfaces (cmd/api/file/env). 4. §V: invariants V1… numbered testable caveman, symbols → ∀ ∃ ! ⊥ ≠ ≤. 5. §T: pipe table id|status|task|cites all status='.'. 6. §B: header row only id|date|cause|fix.
Format: drop articles/filler/aux verbs. Preserve code/paths verbatim.
Write file. Show full content. Ask: 'spec OK? suggest edits or /build.'"
      elif [[ "$_sa" == bug:* ]]; then
        _si="[/spec BACKPROP] Bug: ${_sa#bug:}
1. Parse bug. 2. Read code → root cause. 3. Draft V<next> invariant. 4. Append §B: B<n>|$(date +%Y-%m-%d)|<cause>|V<n>. 5. Append §V entry. 6. Update §T if behavior changes. 7. Show diff. Apply on OK."
      elif [[ "$_sa" == amend* ]]; then
        _si="[/spec AMEND] Target: $_sa. Read section. Show current. Ask what changes. Write. Show diff. Never rewrite sections not named."
      elif [[ "$_sa" == from-code* ]]; then
        _si="[/spec DISTILL] Infer SPEC.md from $WORKDIR codebase. §G from README/package.json, §C from stack, §I from public APIs/CLIs, §V from tests/assertions, §T one per TODO or missing test, §B empty. Flag uncertain with ?."
      else
        _si="[/spec] SPEC.md exists. Args: '${_sa:-(none)}'. Determine mode: section ref like §V.3 → AMEND; empty → ask user; description → ask clarification."
      fi
      run_agent "$_si"
      ;;
    /build*)
      [ ! -f "$WORKDIR/SPEC.md" ] && { echo "  No SPEC.md — run /spec first."; return 0; }
      local _ba="${1#/build}"; _ba="${_ba# }"
      local _bi="[/build] Execute §T tasks in $WORKDIR/SPEC.md. Args: '${_ba:-(all . tasks)}'.
Task select: §T.n=that task / --next=lowest . row / --all or empty=all . rows.
Per task: 1. Cite §V + §I that apply. List files/tests. Name verify cmd. Show plan.
2. Flip §T status . → ~ in SPEC.md. Implement. Run verify.
   Pass → flip ~ → x. Commit: 'T<n>: <goal>'. Next.
   Fail → backprop: (a) code bug=fix+retry (b) spec gap=run /spec bug: <cause> first.
Write policy: only flip §T status. All other spec edits via /spec. No sub-agents."
      run_agent "$_bi"
      ;;
    /check*)
      [ ! -f "$WORKDIR/SPEC.md" ] && { echo "  No SPEC.md — run /spec first."; return 0; }
      local _ca="${1#/check}"; _ca="${_ca# }"
      local _ci="[/check] Drift report. Zero writes. Target: '${_ca:-(§V)}'.
§V: per invariant grep/read code → HOLD / VIOLATE / UNVERIFIABLE + file:line.
§I: per interface locate impl → MATCH / DRIFT / MISSING / EXTRA.
§T: verify x rows have evidence → flag STALE. Note wip/todo.
Report caveman grouped by severity. End with one-line remedy hints per class. Write nothing."
      run_agent "$_ci"
      ;;
    /test*)
      handle_test_cmd "$1"
      ;;
    *) return 1 ;;
  esac
  return 0
}

