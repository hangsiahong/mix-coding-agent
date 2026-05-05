#!/usr/bin/env bash
# ─── mix build script ────────────────────────────────────────────────────────
# Concatenates src/*.sh into a single executable binary with versioning.

# Bump version on each build
MIX_VERSION="${MIX_VERSION:-$(date +%Y%m%d%H%M)}"
export MIX_VERSION

echo '#!/usr/bin/env bash' > mix.compiled
# Embed version as the very first line after shebang
echo "MIX_VERSION='$MIX_VERSION'" >> mix.compiled

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
    src/09b_proactive_memory.sh \
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
    src/26_banner.sh

# Main REPL loop — MUST come last, since it blocks forever
cat src/27_main_repl.sh >> mix.compiled

# Safety: ensure newline at end of binary
echo "" >> mix.compiled

cp mix.compiled mix
chmod +x mix.compiled mix
echo "Compiled to mix (and mix.compiled)!"

# ─── Health gate: only version + install if binary passes self-test ──────────
_self_test_out=$(bash mix --self-test 2>&1)
_self_test_rc=$?
if [ $_self_test_rc -ne 0 ]; then
  echo "⚠️  Self-test FAILED — binary not installed or versioned:"
  echo "$_self_test_out" | head -5
  exit 1
fi
echo "✓ Self-test passed"

# ─── Version the binary ─────────────────────────────────────────────────────
_VERSIONS_DIR="$HOME/.mix/versions"
mkdir -p "$_VERSIONS_DIR"

# Timestamped backup
_TS=$(date +%s)
_VERSIONED_BIN="$_VERSIONS_DIR/${_TS}.bin"
cp mix "$_VERSIONED_BIN"
echo "✓ Versioned → ${_TS}.bin"

# Update last_good (keep previous current if it exists)
if [ -L "$_VERSIONS_DIR/current" ] && [ -f "$_VERSIONS_DIR/current" ]; then
  _prev_current=$(readlink -f "$_VERSIONS_DIR/current" 2>/dev/null)
  if [ -n "$_prev_current" ] && [ "$_prev_current" != "$_VERSIONED_BIN" ]; then
    ln -sfn "$_prev_current" "$_VERSIONS_DIR/last_good"
    echo "✓ last_good → $(basename "$_prev_current")"
  fi
fi

# Update current symlink
ln -sfn "$_VERSIONED_BIN" "$_VERSIONS_DIR/current"
echo "✓ current → ${_TS}.bin"

# ─── Auto-prune: keep last 5 versions ───────────────────────────────────────
_prune_count=0
_cur_target=$(readlink -f "$_VERSIONS_DIR/current" 2>/dev/null)
_lg_target=$(readlink -f "$_VERSIONS_DIR/last_good" 2>/dev/null)
for _old in $(ls -1t "$_VERSIONS_DIR/"*.bin 2>/dev/null | tail -n +6); do
  _old_real=$(readlink -f "$_old" 2>/dev/null)
  [ "$_old_real" = "$_cur_target" ] && continue
  [ "$_old_real" = "$_lg_target" ] && continue
  rm -f "$_old"
  ((_prune_count++)) || true
done
[ $_prune_count -gt 0 ] && echo "✓ Pruned $_prune_count old version(s)"

# ─── Install: write thin wrapper to PATH ────────────────────────────────────
_install_target=""
for _d in "$HOME/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  if echo "$PATH" | tr ':' '\n' | grep -qx "$_d" && [ -d "$_d" ]; then
    _install_target="$_d/mix"
    break
  fi
done

if [ -n "$_install_target" ]; then
  cat > "$_install_target" << 'WRAPPER'
#!/bin/bash
# mix wrapper — health-checks the current binary, falls back to last_good
# This file is intentionally simple (~30 lines). It should NEVER break.
MIX_DIR="$HOME/.mix/versions"
CRASH_LOG="/tmp/mix-crash.log"
CURRENT="$MIX_DIR/current"
LAST_GOOD="$MIX_DIR/last_good"

# No versions installed yet? Try running from source tree
if [ ! -f "$CURRENT" ]; then
  for _try in "./mix" "$(dirname "$0")/../mix"; do
    [ -f "$_try" ] && exec bash "$_try" "$@"
  done
  echo "mix: no binary found. Run install.sh or build.sh first." >&2
  exit 1
fi

# Quick health check — 3 second timeout
_test_out=$(timeout 3 bash "$CURRENT" --self-test 2>"$CRASH_LOG")
_test_rc=$?
if [ $_test_rc -eq 0 ] && [ "$_test_out" = "OK" ]; then
  exec bash "$CURRENT" "$@"
fi

# Current binary is broken — try last_good in --doctor mode
echo "⚠️  Broken build detected." >&2
if [ -f "$CRASH_LOG" ]; then
  echo "  Last error:" >&2
  head -3 "$CRASH_LOG" | sed 's/^/    /' >&2
fi

if [ -f "$LAST_GOOD" ]; then
  echo "  Booting last_good in --doctor mode..." >&2
  exec bash "$LAST_GOOD" --doctor "$@"
fi

# Catastrophic — no working binary
echo "  No last_good binary available." >&2
echo "  Manual recovery: cd to source dir and run 'bash build.sh'" >&2
exit 1
WRAPPER
  chmod +x "$_install_target"
  echo "Installed wrapper → $_install_target"
fi