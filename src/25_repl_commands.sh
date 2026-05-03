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
      MODEL="${1#/model }"
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
      echo "  agent:   /flush  /compact  /model [id]  /models  /provider [name]  /history  /caveman [off|lite|full|ultra]  /mode [fast|deep|plan]  /yolo  /workers  /worker <name> <cmd>  /subagent <name> <task>  /afk [hint]  /afk log  /afk stop  /skill <name>  /skills  /help  /exit"
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
    /afk\ status|/afk\ log)
      local _afklog="${MIX_AFK_LOG:-}"
      if [ -z "$_afklog" ] || [ ! -f "$_afklog" ]; then
        # find most recent afk log
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
    /afk*)
      local _afk_hint="${1#/afk}"; _afk_hint="${_afk_hint# }"
      local _afk_log="/tmp/mix-afk-$(date +%s).log"
      local _afk_prompt
      read -r -d '' _afk_prompt <<'AFKPROMPT'
[AFK AUTOPILOT] You are running autonomously while the user is away. Work through this checklist — do as many items as you can, skipping items that don't apply or are already clean. Be proactive and make real changes. Log a summary when done.

CHECKLIST (work top-down, commit small wins as you go):
1. SCAN for TODO/FIXME/HACK/NOFIX comments in src/ — for each: attempt a real fix, then remove the comment if solved.
2. BUGS: Read recent git log (last 10 commits) and any SPEC.md or README for known issues. Look for obvious logic bugs, off-by-ones, unquoted variables, missing error checks in shell scripts. Fix what you can.
3. TESTS: If a TEST_CMD env var is set, run it and fix failures. If tests pass, note that.
4. DEAD CODE: Look for functions defined but never called, variables set but unused, commented-out code blocks older than 2 weeks (via git blame). Remove or annotate.
5. MEMORYBANK: If memorybank/log.md exists, append a brief entry: date, what was changed, what was found, reasoning. If memorybank/index.md is stale, update it.
6. GLOBAL MEMORY: Use update_global_memory to record any useful patterns, conventions, or "aha" moments observed during this session.
7. README/DOCS: If README.md or any .md doc is factually wrong (wrong command, wrong filename, outdated section), fix it.
8. STYLE: In shell scripts, fix obvious style issues (e.g. missing quotes around variables in critical paths, inconsistent indentation) only if safe to do. Don't refactor just for aesthetics.
9. SECURITY: Scan for obvious shell injection risks (e.g. unquoted $vars in eval or command substitution). Fix if found.
10. BONUS: Do one surprising-but-useful thing: write a missing util, add a helpful alias, document a tricky piece of logic, or generate a quick health-check script.

WHEN DONE: Write a brief AFK REPORT to memorybank/log.md (or stdout if not available) listing: items checked, items fixed, items skipped + why, and one recommendation for the user.

Be decisive. Prefer doing over asking. If something is risky, skip it and note why in the report.
AFKPROMPT

      if [ -n "$_afk_hint" ]; then
        _afk_prompt="$_afk_prompt

USER HINT: $_afk_hint"
      fi

      if [ -n "$TMUX" ]; then
        local _stmp _mytty
        _stmp=$(mktemp -t mix-afk-XXXXXX)
        _mytty=$(tty)
        printf '%s\n' "$_afk_prompt" > "$_stmp"
        tmux new-window -n "mix-afk" "bash -c 'cat $_stmp | mix 2>&1 | tee $_afk_log; rm -f $_stmp; echo -e \"\n  \033[38;5;82m✓ AFK done!\033[0m Log: $_afk_log\" > $_mytty; echo \"\"; echo \"[AFK finished. Press Enter]\"; read -r'" 2>/dev/null
        if [ $? -eq 0 ]; then
          MIX_AFK_LOG="$_afk_log"
          MIX_AFK_WIN="mix-afk"
          printf '  \033[38;5;99m🌙 AFK mode active\033[0m — working in background (tmux window: mix-afk)\n'
          printf '  Log: %s\n' "$_afk_log"
          printf '  Check back: /afk log   Stop early: /afk stop\n'
        else
          echo "  Failed to spawn AFK worker."
        fi
      else
        # No tmux: offer to run inline
        printf '  \033[38;5;220m⚠ Not in tmux — run AFK inline? This will block until done. [y/N] \033[0m'
        local _yn
        read -r _yn < /dev/tty
        if [[ "$_yn" =~ ^[Yy]$ ]]; then
          MIX_AFK_LOG="$_afk_log"
          printf '  \033[38;5;99m🌙 AFK mode (inline)\033[0m — logging to %s\n' "$_afk_log"
          run_agent "$_afk_prompt"
        else
          echo "  Aborted. Start tmux and try again for background mode."
        fi
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

