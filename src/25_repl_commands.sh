# ─── REPL Commands ──────────────────────────────────────────────────────────
handle_cmd() {
  case "$1" in
    /flush)  HISTORY='[]'; rm -f "$HIST_FILE"; echo "  History cleared." ;;
    /model)  echo "  Model: $MODEL" ;;
    /model\ *) MODEL="${1#/model }"; echo "  Model → $MODEL" ;;
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
      echo "  agent:   /flush  /compact  /model [id]  /history  /caveman [off|lite|full|ultra]  /mode [fast|deep|plan]  /yolo  /workers  /worker <name> <cmd>  /subagent <name> <task>  /skill <name>  /skills  /help  /exit"
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
        _stmp=$(mktemp)
        _mytty=$(tty)
        printf '%s\n' "$_stask" > "$_stmp"
        tmux new-window -n "$_sname" "bash -c 'cat $_stmp | mix 2>&1 | tee /tmp/${_sname}.log; rm -f $_stmp; echo -e \"\n  \033[38;5;82m✓ Subagent [$_sname] finished!\033[0m (Ask mix to read /tmp/${_sname}.log)\" > $_mytty; echo \"\"; echo \"[Subagent finished. Press Enter to close]\"; read -r'" 2>/dev/null \
          && echo "  ↳ subagent [$_sname] spawned logging to /tmp/${_sname}.log" \
          || echo "  Failed to spawn subagent."
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

