# ─── REPL Commands ──────────────────────────────────────────────────────────
handle_cmd() {
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
    /flush)  HISTORY='[]'; rm -f "$HIST_FILE"; echo "  History cleared." ;;
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
    /help)
      echo "  cavekit: /spec [idea|bug:|amend|from-code]  /build [§T.n|--next|--all]  /check [§V|§I|§T|--all]"
      echo "  agent:   /flush  /compact  /model [id]  /models  /provider [name]  /history  /caveman [off|lite|full|ultra]  /mode [fast|deep|plan]  /yolo  /workers  /worker <name> <cmd>  /subagent <name> <task>  /afk [hint]  /afk log  /afk stop  /afk setup  /afk apply  /skill <name>  /skills  /help  /exit"
      ;;
    /skills)
      if [ -z "$ACTIVE_SKILLS" ]; then
        echo "  No active skills."
      else
        echo "  Active skills:"
        for s in $ACTIVE_SKILLS; do echo "    - $s"; done
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
      local _afklog="${MIX_AFK_LOG:-}"
      if [ -z "$_afklog" ] || [ ! -f "$_afklog" ]; then
        _afklog=$(ls -t /tmp/mix-afk-*.log 2>/dev/null | head -1)
      fi
      if [ -z "$_afklog" ]; then
        echo "  No AFK log found."
      else
        echo "  ── AFK log: $_afklog ──"
        tail -40 "$_afklog"
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
      local _afk_log="/tmp/mix-afk-$(date +%s).log"

      if [ -z "$TMUX" ]; then
        echo "  Not in tmux — AFK requires tmux for background execution."
        return 0
      fi

      # Decide mode: Telegram or plan-file-only
      local _use_tg=false
      if telegram_is_configured 2>/dev/null; then
        _use_tg=true
      fi

      # Write plan-only prompt to temp file (avoids quote hell in worker script)
      local _plan_tmp; _plan_tmp=$(mktemp -t mix-afk-plan-XXXXXX)
      local _apply_tmp; _apply_tmp=$(mktemp -t mix-afk-apply-XXXXXX)
      local _worker_tmp; _worker_tmp=$(mktemp -t mix-afk-worker-XXXXXX)

      cat > "$_plan_tmp" << 'PLAN_PROMPT_END'
[AFK PLAN MODE — READ ONLY] The user is away. Analyse the codebase and produce a structured plan. Do NOT use edit_file, create_file, or bash commands with side effects. Only use read_file, search_files, and read-only bash (cat, grep, git log, git status, git diff, find, wc).

Work through this analysis:
1. SCAN: grep for TODO/FIXME/HACK/BUG in src/ — list file:line for each
2. BUGS: Read git log --oneline -15. Look for obvious logic bugs, unquoted shell vars, missing error checks in critical paths
3. SECURITY: Any obvious injection risks (eval with unquoted vars, curl piped to bash, etc.)
4. DEAD CODE: Functions defined but never called or variables always overwritten before use
5. DOCS: Is README.md accurate? Any named files/commands that no longer exist?

CRITICAL OUTPUT FORMAT — end your final response with EXACTLY this block (required for Telegram delivery):

## AFK PLAN
### 1. [Title]
Rationale: [why this matters]
Files: [which files]
Risk: low/med/high

### 2. [Title]
...

## END PLAN
PLAN_PROMPT_END

      # Append user hint if given
      [ -n "$_afk_hint" ] && printf '\nUser hint: %s\n' "$_afk_hint" >> "$_plan_tmp"

      cat > "$_apply_tmp" << 'APPLY_PREFIX_END'
[AFK APPLY MODE] The user reviewed and approved this plan via Telegram. Execute each item using edit_file and bash. Read each file before editing. Make minimal targeted changes. Do not touch anything outside the plan scope.

Plan to execute:
APPLY_PREFIX_END

      # Write self-contained worker script (single-quoted heredoc = no expansion here)
      cat > "$_worker_tmp" << 'AFK_WORKER_END'
#!/usr/bin/env bash
set -uo pipefail
PLAN_FILE="$1"
APPLY_PREFIX_FILE="$2"
LOG_FILE="$3"
WORKDIR="$4"
MY_TTY="$5"
USE_TG="$6"
cd "$WORKDIR" || exit 1

TG_CONFIG="$HOME/.mix/telegram"
TG_TOKEN=$(grep '^BOT_TOKEN=' "$TG_CONFIG" 2>/dev/null | cut -d= -f2- || true)
TG_CHAT=$(grep '^CHAT_ID=' "$TG_CONFIG" 2>/dev/null | cut -d= -f2- || true)
MIX_BIN=$(command -v mix 2>/dev/null)
PLAN_SAVE="$HOME/.mix/afk-plan.md"

tg_send() {
    [ "$USE_TG" != "true" ] && return 0
    local text="$1"
    python3 - "$text" "$TG_TOKEN" "$TG_CHAT" << 'PYEOF'
import sys, json, urllib.request
text, token, chat = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({'chat_id': chat, 'text': text, 'parse_mode': 'Markdown'}).encode()
req = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/sendMessage',
    data=payload, headers={'Content-Type': 'application/json'})
try: urllib.request.urlopen(req, timeout=10)
except: pass
PYEOF
}

tg_send_buttons() {
    [ "$USE_TG" != "true" ] && return 0
    local text="$1"
    python3 - "$text" "$TG_TOKEN" "$TG_CHAT" << 'PYEOF'
import sys, json, urllib.request
text, token, chat = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({
    'chat_id': chat, 'text': text, 'parse_mode': 'Markdown',
    'reply_markup': {'inline_keyboard': [[
        {'text': '✅ Apply', 'callback_data': 'afk_yes'},
        {'text': '❌ Skip',  'callback_data': 'afk_no'}
    ]]}
}).encode()
req = urllib.request.Request(
    f'https://api.telegram.org/bot{token}/sendMessage',
    data=payload, headers={'Content-Type': 'application/json'})
try: urllib.request.urlopen(req, timeout=10)
except: pass
PYEOF
}

tg_poll() {
    local timeout_secs="${1:-7200}"
    local deadline=$(( $(date +%s) + timeout_secs ))
    # Get current offset to skip stale callbacks
    local init offset=0
    init=$(curl -s --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?limit=1&offset=-1" 2>/dev/null || echo '{"result":[]}')
    offset=$(python3 -c "
import json,sys
r=json.loads(sys.argv[1]).get('result',[])
print(r[-1].get('update_id',0)+1 if r else 0)" "$init" 2>/dev/null || echo 0)

    while [ "$(date +%s)" -lt "$deadline" ]; do
        local resp
        resp=$(curl -s --max-time 35 \
            "https://api.telegram.org/bot${TG_TOKEN}/getUpdates?offset=${offset}&timeout=30&allowed_updates=%5B%22callback_query%22%5D" \
            2>/dev/null) || { sleep 5; continue; }
        local result
        result=$(python3 -c "
import json,sys
try:
    data=json.loads(sys.argv[1])
    if not data.get('ok'): sys.exit(0)
    for u in data.get('result',[]):
        uid=u.get('update_id',0)
        cb=u.get('callback_query',{})
        d=cb.get('data','')
        if d in ('afk_yes','afk_no'):
            print(str(uid+1)+':'+cb.get('id','')+':'+d); break
except: pass
" "$resp" 2>/dev/null || true)

        if [ -n "$result" ]; then
            local cb_id="${result#*:}"; cb_id="${cb_id%%:*}"
            local answer="${result##*:}"
            [ -n "$cb_id" ] && curl -s --max-time 5 -X POST \
                "https://api.telegram.org/bot${TG_TOKEN}/answerCallbackQuery" \
                -d "callback_query_id=${cb_id}" > /dev/null 2>&1 || true
            printf '%s' "${answer#afk_}"; return 0
        fi
    done
    printf 'timeout'
}

PROJECT="$(basename "$WORKDIR")"
echo "  🌙 AFK worker started — project: $PROJECT"
tg_send "🤖 *mix AFK started*
📁 Project: \`${PROJECT}\`
🕐 $(date '+%H:%M %Z')
_Analysing codebase (read-only mode)..._"

# Step 1: Run plan-only analysis
echo "  Analysing (read-only)..."
"$MIX_BIN" < "$PLAN_FILE" 2>&1 | tee "$LOG_FILE"

# Step 2: Extract plan from log output (strip ANSI codes)
PLAN=$(python3 - "$LOG_FILE" << 'PYEOF'
import sys, re
try:
    text = open(sys.argv[1]).read()
    ansi = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    text = ansi.sub('', text)
    m = re.search(r'## AFK PLAN\n(.*?)(?:## END PLAN|\Z)', text, re.DOTALL)
    if m:
        print(m.group(1).strip()[:2800])
    else:
        # Fallback: last agent response block
        parts = text.split('\u25c6 mix')
        last = parts[-1].strip() if len(parts) > 1 else text[-2000:].strip()
        print(last[:2800])
except Exception as e:
    print(f'(Error extracting plan: {e})')
PYEOF
)

[ -z "$PLAN" ] && PLAN="(Agent produced no structured plan — check log: $LOG_FILE)"

# Save plan to file
{ echo "# AFK Plan — $(date '+%Y-%m-%d %H:%M')"; echo "## Project: $PROJECT"; echo ""; printf '%s\n' "$PLAN"; } > "$PLAN_SAVE"
echo ""
echo "  ── Plan saved to $PLAN_SAVE ──"

if [ "$USE_TG" = "true" ]; then
    # Step 3: Send to Telegram with buttons
    MSG="🗒 *AFK Plan — ${PROJECT}*

${PLAN}

---
_Tap to approve or skip all changes_"
    # Truncate if over Telegram limit
    if [ ${#MSG} -gt 3900 ]; then
        SHORT="${PLAN:0:2500}
..._(truncated — full plan: \`~/.mix/afk-plan.md\`)_"
        MSG="🗒 *AFK Plan — ${PROJECT}*

${SHORT}

---
_Tap to approve or skip_"
    fi
    tg_send_buttons "$MSG"
    tg_send "⏳ _Waiting for your decision (2h timeout)..._"

    # Step 4: Poll for reply
    REPLY=$(tg_poll 7200)
    echo "  Telegram reply: $REPLY"

    case "$REPLY" in
        yes)
            tg_send "✅ *Approved! Applying plan...*"
            APPLY_PROMPT="$(cat "$APPLY_PREFIX_FILE")
${PLAN}"
            MIX_YOLO=1 "$MIX_BIN" <<< "$APPLY_PROMPT" 2>&1 | tee "${LOG_FILE%.log}-apply.log"
            tg_send "✅ *Done applying!*
Log: \`${LOG_FILE%.log}-apply.log\`
Back at keyboard? Run \`/afk status\` in mix."
            ;;
        no)
            tg_send "❌ *Skipped.*
Plan saved: \`~/.mix/afk-plan.md\`
Run \`/afk apply\` in mix when ready."
            ;;
        timeout)
            tg_send "⏰ *Timed out* (2h without response).
Plan saved: \`~/.mix/afk-plan.md\`
Run \`/afk apply\` in mix when ready."
            ;;
    esac
else
    echo "  (No Telegram configured — plan saved to $PLAN_SAVE)"
    echo "  Run /afk apply to execute, or review the plan first."
fi

# Notify the main terminal
[ -n "$MY_TTY" ] && printf '\n  \033[38;5;82m✓ AFK done!\033[0m Log: %s\n' "$LOG_FILE" > "$MY_TTY" 2>/dev/null || true
echo ""
echo "[AFK finished. Press Enter]"
read -r _
AFK_WORKER_END
      chmod +x "$_worker_tmp"

      local _mytty; _mytty=$(tty 2>/dev/null || echo "")
      tmux new-window -n "mix-afk" \
        "bash '$_worker_tmp' '$_plan_tmp' '$_apply_tmp' '$_afk_log' '$PWD' '$_mytty' '$_use_tg'; rm -f '$_plan_tmp' '$_apply_tmp' '$_worker_tmp'" \
        2>/dev/null
      if [ $? -eq 0 ]; then
        MIX_AFK_LOG="$_afk_log"
        MIX_AFK_WIN="mix-afk"
        printf '  \033[38;5;99m🌙 AFK mode active\033[0m — working in background\n'
        printf '  Log: %s\n' "$_afk_log"
        if [ "$_use_tg" = "true" ]; then
          printf '  Telegram: plan will be sent for approval\n'
        else
          printf '  \033[38;5;220m⚠ No Telegram configured.\033[0m Run \033[1m/afk setup\033[0m to enable phone approval.\n'
          printf '  Plan will be saved to ~/.mix/afk-plan.md — run /afk apply to execute.\n'
        fi
        printf '  Check back: /afk log   Stop: /afk stop\n'
      else
        echo "  Failed to spawn AFK worker."
        rm -f "$_plan_tmp" "$_apply_tmp" "$_worker_tmp"
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
    *) return 1 ;;
  esac
  return 0
}

