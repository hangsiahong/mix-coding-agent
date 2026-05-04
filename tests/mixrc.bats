#!/usr/bin/env bats
# Tests for .mixrc project overrides (src/02_mixrc.sh)

setup() {
  export WORKDIR="$(mktemp -d)"
  export HOME="$(mktemp -d)"
  mkdir -p "$HOME/.mix"
  # Source minimal deps
  source src/02_mixrc.sh
}

teardown() {
  rm -rf "$WORKDIR" "$HOME"
}

# ─── _mixrc_load ─────────────────────────────────────────────────────────────

@test "mixrc_load returns silently when no .mixrc exists" {
  run _mixrc_load
  [ "$status" -eq 0 ]
  [ "$_MIXRC_LOADED" = "false" ]
}

@test "mixrc_load reads MODEL from .mixrc" {
  printf 'MODEL=gpt-4o\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
  [ "$_MIXRC_LOADED" = "true" ]
}

@test "mixrc_load reads CAVEMAN_MODE from .mixrc" {
  printf 'CAVEMAN_MODE=ultra\n' > "$WORKDIR/.mixrc"
  CAVEMAN_MODE="full"
  _mixrc_load
  [ "$CAVEMAN_MODE" = "ultra" ]
}

@test "mixrc_load reads AGENT_MODE from .mixrc" {
  printf 'AGENT_MODE=deep\n' > "$WORKDIR/.mixrc"
  AGENT_MODE="fast"
  _mixrc_load
  [ "$AGENT_MODE" = "deep" ]
}

@test "mixrc_load reads AUTO_YES from .mixrc" {
  printf 'AUTO_YES=false\n' > "$WORKDIR/.mixrc"
  AUTO_YES="true"
  _mixrc_load
  [ "$AUTO_YES" = "false" ]
}

@test "mixrc_load reads MAX_TURNS from .mixrc" {
  printf 'MAX_TURNS=50\n' > "$WORKDIR/.mixrc"
  MAX_TURNS="100"
  _mixrc_load
  [ "$MAX_TURNS" = "50" ]
}

@test "mixrc_load reads AUTO_VERIFY from .mixrc" {
  printf 'AUTO_VERIFY=on\n' > "$WORKDIR/.mixrc"
  AUTO_VERIFY="off"
  _mixrc_load
  [ "$AUTO_VERIFY" = "on" ]
}

@test "mixrc_load reads VERIFY_CMD from .mixrc" {
  printf 'VERIFY_CMD=npm run lint && npm test\n' > "$WORKDIR/.mixrc"
  VERIFY_CMD=""
  _mixrc_load
  [ "$VERIFY_CMD" = "npm run lint && npm test" ]
}

@test "mixrc_load reads STREAM from .mixrc" {
  printf 'STREAM=false\n' > "$WORKDIR/.mixrc"
  STREAM="true"
  _mixrc_load
  [ "$STREAM" = "false" ]
}

@test "mixrc_load skips comments" {
  printf '# this is a comment\nMODEL=gpt-4o\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
}

@test "mixrc_load skips blank lines" {
  printf '\n\nMODEL=gpt-4o\n\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
}

@test "mixrc_load strips quotes from values" {
  printf 'MODEL="gpt-4o"\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
}

@test "mixrc_load strips single quotes from values" {
  printf "MODEL='gpt-4o'\n" > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
}

@test "mixrc_load ignores unknown keys" {
  printf 'UNKNOWN_KEY=evil\nMODEL=gpt-4o\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
  [ -z "$UNKNOWN_KEY" ]
}

@test "mixrc_load reads multiple keys" {
  printf 'MODEL=gpt-4o\nCAVEMAN_MODE=ultra\nAGENT_MODE=deep\n' > "$WORKDIR/.mixrc"
  MODEL="glm-5"
  CAVEMAN_MODE="full"
  AGENT_MODE="fast"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
  [ "$CAVEMAN_MODE" = "ultra" ]
  [ "$AGENT_MODE" = "deep" ]
}

@test "mixrc_load env var wins over .mixrc for MODEL" {
  printf 'MODEL=gpt-4o\n' > "$WORKDIR/.mixrc"
  AGENT_MODEL="glm-5"
  MODEL="$AGENT_MODEL"
  _mixrc_load
  [ "$MODEL" = "glm-5" ]
}

@test "mixrc_load walks up to parent directory" {
  local subdir="$WORKDIR/src/deep/nested"
  mkdir -p "$subdir"
  printf 'MODEL=gpt-4o\n' > "$WORKDIR/.mixrc"
  WORKDIR="$subdir"
  MODEL="glm-5"
  AGENT_MODEL=""
  _mixrc_load
  [ "$MODEL" = "gpt-4o" ]
}

@test "mixrc_load reads BASE_URL from .mixrc" {
  printf 'BASE_URL=http://localhost:8080/v1\n' > "$WORKDIR/.mixrc"
  BASE_URL="https://ai.koompi.cloud/v1"
  AGENT_BASE_URL=""
  _mixrc_load
  [ "$BASE_URL" = "http://localhost:8080/v1" ]
}

@test "mixrc_load reads PROVIDER from .mixrc" {
  printf 'PROVIDER=copilot\n' > "$WORKDIR/.mixrc"
  PROVIDER="default"
  AGENT_PROVIDER=""
  _mixrc_load
  [ "$PROVIDER" = "copilot" ]
}

@test "mixrc_load reads REPO_MAP_TTL from .mixrc" {
  printf 'REPO_MAP_TTL=300\n' > "$WORKDIR/.mixrc"
  _REPO_MAP_TTL=600
  REPO_MAP_TTL=""
  _mixrc_load
  [ "$_REPO_MAP_TTL" = "300" ]
}

# ─── _mixrc_show ─────────────────────────────────────────────────────────────

@test "mixrc_show shows loaded file when .mixrc loaded" {
  printf 'MODEL=gpt-4o\nCAVEMAN_MODE=ultra\n' > "$WORKDIR/.mixrc"
  AGENT_MODEL=""
  _mixrc_load
  run _mixrc_show
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Loaded from" ]]
  [[ "$output" =~ "MODEL" ]]
  [[ "$output" =~ "gpt-4o" ]]
}

@test "mixrc_show shows no .mixrc message when not loaded" {
  _MIXRC_LOADED=false
  run _mixrc_show
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No .mixrc found" ]]
}

@test "mixrc_load reads GIT_ENABLED from .mixrc" {
  printf 'GIT_ENABLED=true\n' > "$WORKDIR/.mixrc"
  GIT_ENABLED=false
  _mixrc_load
  [ "$GIT_ENABLED" = "true" ]
}

@test "mixrc_load reads TEST_CMD from .mixrc" {
  printf 'TEST_CMD=npm test\n' > "$WORKDIR/.mixrc"
  TEST_CMD=""
  _mixrc_load
  [ "$TEST_CMD" = "npm test" ]
}

@test "mixrc_load reads MAX_HIST_MSGS from .mixrc" {
  printf 'MAX_HIST_MSGS=30\n' > "$WORKDIR/.mixrc"
  MAX_HIST_MSGS=60
  _mixrc_load
  [ "$MAX_HIST_MSGS" = "30" ]
}

@test "mixrc_load reads CTX_TOKENS from .mixrc" {
  printf 'CTX_TOKENS=65536\n' > "$WORKDIR/.mixrc"
  CTX_TOKENS=131072
  _mixrc_load
  [ "$CTX_TOKENS" = "65536" ]
}

@test "mixrc_load reads MAX_FAIL_STREAK from .mixrc" {
  printf 'MAX_FAIL_STREAK=8\n' > "$WORKDIR/.mixrc"
  MAX_FAIL_STREAK=4
  _mixrc_load
  [ "$MAX_FAIL_STREAK" = "8" ]
}
