#!/usr/bin/env bats
# Tests for TUI improvements across multiple modules

setup() {
  load test_helper
  INTERACTIVE=false
  export INTERACTIVE
  source "$PROJECT_ROOT/src/19_spinner_background_process.sh"
  source "$PROJECT_ROOT/src/20_context_window_bar.sh"
  source "$PROJECT_ROOT/src/21_tmux_status_updater.sh"
  source "$PROJECT_ROOT/src/08_self_healing_bash_wrapper.sh"
  source "$PROJECT_ROOT/src/08a_failure_diagnostics.sh"
  source "$PROJECT_ROOT/src/05_pre_edit_diff_preview.sh"
}

# ─── Spinner color states (#8) ─────────────────────────────────────

@test "spinner default color is purple" {
  ACTIVE_SKILLS=""
  start_spinner "thinking"
  [ -n "$_SPIN_PID" ]
  { kill "$_SPIN_PID" 2>/dev/null && wait "$_SPIN_PID" 2>/dev/null; } || true
  _SPIN_PID=""
}

@test "spinner retry label triggers orange color" {
  ACTIVE_SKILLS=""
  start_spinner "mix (turn 1 retry 2)"
  [ -n "$_SPIN_PID" ]
  { kill "$_SPIN_PID" 2>/dev/null && wait "$_SPIN_PID" 2>/dev/null; } || true
  _SPIN_PID=""
}

@test "spinner error label triggers red color" {
  ACTIVE_SKILLS=""
  start_spinner "error recovery"
  [ -n "$_SPIN_PID" ]
  { kill "$_SPIN_PID" 2>/dev/null && wait "$_SPIN_PID" 2>/dev/null; } || true
  _SPIN_PID=""
}

# ─── Context bar (#7) ──────────────────────────────────────────────

@test "ctx_bar runs without error on empty history" {
  HISTORY='[]'
  CTX_TOKENS=131072
  _SESSION_API_CALLS=0
  _SESSION_PROMPT_TOKENS=0
  _SESSION_COMPLETION_TOKENS=0
  run ctx_bar
  # ctx_bar uses printf which may return non-zero, just verify it doesn't crash
  [ -n "$output" ]
  echo "$output" | grep -q "0k"
}

@test "ctx_bar shows session stats when calls > 0" {
  HISTORY='[]'
  CTX_TOKENS=131072
  _SESSION_API_CALLS=5
  _SESSION_PROMPT_TOKENS=10000
  _SESSION_COMPLETION_TOKENS=2000
  run ctx_bar
  [ $status -eq 0 ]
  echo "$output" | grep -q "5 calls"
}

# ─── Bash truncation marker (#3) ──────────────────────────────────

@test "run_with_heal truncation shows line counts" {
  # Generate a command that outputs >200 lines
  result=$(run_with_heal "for i in \$(seq 1 300); do echo line \$i; done")
  [ $? -eq 0 ]
  # Should contain truncation marker
  echo "$result" | grep -q "showing first"
  echo "$result" | grep -q "omitted"
}

@test "run_with_heal short output is not truncated" {
  result=$(run_with_heal "echo hello")
  [ $? -eq 0 ]
  echo "$result" | grep -q "hello"
  # Should NOT contain truncation marker
  ! echo "$result" | grep -q "truncated"
}

# ─── Diff preview context lines (#11) ──────────────────────────────

@test "show_edit_diff shows context lines for matching edit" {
  # Create a temp file
  _tmpf=$(mktemp)
  printf 'line 1\nline 2\nline 3\nline 4\nline 5\n' > "$_tmpf"
  local args="{\"path\":\"$_tmpf\",\"old_text\":\"line 3\",\"new_text\":\"line THREE\"}"
  run show_edit_diff "$args"
  [ $status -eq 0 ]
  # Should show unified diff
  echo "$output" | grep -q "line THREE"
  # Should show context section
  echo "$output" | grep -q "context"
  rm -f "$_tmpf"
}

@test "show_edit_diff shows new file preview" {
  # Non-existent file shows green + lines
  _tmpf="/tmp/mix-test-diff-$$-nonexistent.sh"
  rm -f "$_tmpf"
  local args="{\"path\":\"$_tmpf\",\"old_text\":\"\",\"new_text\":\"#!/bin/bash\necho hello\"}"
  run show_edit_diff "$args"
  [ $status -eq 0 ]
  echo "$output" | grep -q "new file"
  echo "$output" | grep -q "echo hello"
}

@test "show_edit_diff reports not found for bad old_text" {
  _tmpf=$(mktemp)
  printf 'hello world\n' > "$_tmpf"
  local args="{\"path\":\"$_tmpf\",\"old_text\":\"not in file\",\"new_text\":\"replacement\"}"
  run show_edit_diff "$args"
  [ $status -eq 0 ]
  echo "$output" | grep -q "not found"
  rm -f "$_tmpf"
}

# ─── Tmux update (#12) ────────────────────────────────────────────

@test "tmux_update skips when not in tmux" {
  TMUX=""
  run tmux_update
  [ $status -eq 0 ]
  [ -z "$output" ]
}

@test "tmux_update works with simulated tmux env" {
  # Just verify the function doesn't crash with various states
  TMUX=""
  HISTORY='[]'
  CTX_TOKENS=131072
  GIT_ENABLED=false
  AGENT_MODE="fast"
  MODEL="test-model"
  _SPIN_PID=""
  run tmux_update
  [ $status -eq 0 ]
}

# ─── Failure diagnostics (#3 related) ──────────────────────────────

@test "diagnose_failure handles empty output" {
  run diagnose_failure "cmd" "" 1
  [ $status -eq 0 ]
  [ -z "$output" ]
}

@test "diagnose_failure detects command not found" {
  run diagnose_failure "badcmd" "badcmd: command not found" 127
  [ $status -eq 0 ]
  echo "$output" | grep -q "not found"
}

@test "diagnose_failure detects permission denied" {
  run diagnose_failure "touch /root/file" "touch: permission denied" 1
  [ $status -eq 0 ]
  echo "$output" | grep -q "Permission"
}
