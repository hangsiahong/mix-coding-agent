#!/usr/bin/env bash
# Shebang must be line 1. Write it first, then embed providers so their
# functions exist when src/01_config.sh runs copilot_activate at startup.
echo '#!/usr/bin/env bash' > mix.compiled

for pf in src/providers/*.sh; do
  [ -f "$pf" ] || continue
  echo "# ─── Embedded provider: $(basename "$pf") ───"
  echo "_EMBEDDED_PROVIDER_$(basename "$pf" .sh)=1"
  cat "$pf"
  echo ""
done >> mix.compiled

cat \
    src/00_header.sh \
    src/01_config.sh \
    src/02_mixrc.sh \
    src/02_tmux_bootstrap.sh \
    src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh \
    src/04_project_local_extensions.sh \
    src/04b_extension_system.sh \
    src/05_pre_edit_diff_preview.sh \
    src/06_auto_read_logs_on_bash_failure.sh \
    src/11c_session.sh \
    src/07_environment_detection.sh \
    src/08_self_healing_bash_wrapper.sh \
    src/08a_failure_diagnostics.sh \
    src/09_wiki_solutions_writer.sh \
    src/10_tools_openai_function_calling.sh \
    src/11_history.sh \
    src/11a_file_cache.sh \
    src/11b_repo_map.sh \
    src/12_auto_compact_history.sh \
    src/13_tool_execution.sh \
    src/13a_auto_verify.sh \
    src/14_risk_scoring_blocked_high_med_low_reason.sh \
    src/15_ask_user_for_confirmation_reads_from_dev_tty_not_stdin.sh \
    src/16_api.sh \
    src/17_response_parser.sh \
    src/18_streaming_api_call.sh \
    src/19_spinner_background_process.sh \
    src/20_context_window_bar.sh \
    src/21_tmux_status_updater.sh \
    src/22_process_one_tool_call.sh \
    src/23_lightweight_planning_call_plan_mode.sh \
    src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh \
    src/30_sandbox.sh \
    src/25_repl_commands.sh \
    src/29_telegram.sh \
    src/26a_test_commands.sh \
    src/26_banner.sh \
    >> mix.compiled

# Main REPL loop — MUST come last, since it blocks forever
cat src/27_main_repl.sh >> mix.compiled

cp mix.compiled mix
chmod +x mix.compiled mix
echo "Compiled to mix (and mix.compiled)!"

# Auto-install to the same location install.sh picked
_install_target=""
for _d in "$HOME/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  if echo "$PATH" | tr ':' '\n' | grep -qx "$_d" && [ -d "$_d" ]; then
    _install_target="$_d/mix"
    break
  fi
done
if [ -n "$_install_target" ]; then
  cp mix "$_install_target" && echo "Installed → $_install_target"
fi
