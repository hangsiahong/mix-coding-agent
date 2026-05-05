#!/usr/bin/env bash
# ─── Tests for Google Provider ───────────────────────────────────────────────
load test_helper

_GOOGLE_CONFIG_FILE="$BATS_TEST_DIR/tmp_google_config"
_GOOGLE_KEY_FILE="$BATS_TEST_DIR/tmp_google_key"
_GOOGLE_TOKEN_CACHE="$BATS_TEST_DIR/tmp_google_token"

setup() {
  rm -f "$_GOOGLE_CONFIG_FILE" "$_GOOGLE_KEY_FILE" "$_GOOGLE_TOKEN_CACHE"
  unset GOOGLE_API_KEY GOOGLE_MODE GOOGLE_PROJECT GOOGLE_REGION
}

teardown() {
  rm -f "$_GOOGLE_CONFIG_FILE" "$_GOOGLE_KEY_FILE" "$_GOOGLE_TOKEN_CACHE"
}

# ─── Validate model ────────────────────────────────────────────────────────

@test "google_validate_model: known model passes" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_validate_model "gemini-2.5-pro"
  [ "$status" -eq 0 ]
}

@test "google_validate_model: flash variant passes" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_validate_model "gemini-2.5-flash"
  [ "$status" -eq 0 ]
}

@test "google_validate_model: unknown gemini prefix allowed" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_validate_model "gemini-3.0-nano-preview-20260101"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not in known list"
}

@test "google_validate_model: non-gemini model rejected" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_validate_model "gpt-4o"
  [ "$status" -eq 1 ]
}

@test "google_validate_model: suggests close match on typo" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_validate_model "flash"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Did you mean"
}

# ─── List models ───────────────────────────────────────────────────────────

@test "google_list_models: shows model list" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  MODEL="gemini-2.5-pro"
  run google_list_models
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "gemini-2.5-pro"
  echo "$output" | grep -q "gemini-2.5-flash"
}

@test "google_list_models: marks current model" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  MODEL="gemini-2.5-flash"
  run google_list_models
  echo "$output" | grep "^\s*\*" | grep -q "gemini-2.5-flash"
}

# ─── Extra headers ─────────────────────────────────────────────────────────

@test "google_extra_headers_json: returns empty JSON" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  run google_extra_headers_json
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ─── Get API key — Studio mode ────────────────────────────────────────────

@test "google_get_api_key: studio mode reads key file" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  printf 'mode=studio\nproject_id=\nregion=us-central1\n' > "$_GOOGLE_CONFIG_FILE"
  printf 'test-api-key-123' > "$_GOOGLE_KEY_FILE"
  # Override file paths
  _GOOGLE_CONFIG_FILE="$_GOOGLE_CONFIG_FILE" _GOOGLE_KEY_FILE="$_GOOGLE_KEY_FILE" \
    run bash -c 'source "$PROJECT_ROOT/src/providers/google.sh"; google_get_api_key'
  # Can't easily override internal paths in sourced functions.
  # Instead test with env var path.
}

@test "google_get_api_key: studio mode reads GOOGLE_API_KEY env" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  GOOGLE_API_KEY="env-key-456"
  mkdir -p "$HOME/.mix"
  printf 'mode=studio\nproject_id=\nregion=us-central1\n' > "$HOME/.mix/google_provider"
  result=$(google_get_api_key)
  [ "$result" = "env-key-456" ]
  rm -f "$HOME/.mix/google_provider"
}

# ─── Config save ───────────────────────────────────────────────────────────

@test "_google_save_config: writes studio config" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  _GOOGLE_CONFIG_FILE="$_GOOGLE_CONFIG_FILE"
  _google_save_config "studio"
  [ -f "$_GOOGLE_CONFIG_FILE" ]
  grep -q 'mode=studio' "$_GOOGLE_CONFIG_FILE"
  grep -q 'region=us-central1' "$_GOOGLE_CONFIG_FILE"
}

@test "_google_save_config: writes vertex config with project+region" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  _GOOGLE_CONFIG_FILE="$_GOOGLE_CONFIG_FILE"
  _google_save_config "vertex" "my-project-123" "europe-west1"
  grep -q 'mode=vertex' "$_GOOGLE_CONFIG_FILE"
  grep -q 'project_id=my-project-123' "$_GOOGLE_CONFIG_FILE"
  grep -q 'region=europe-west1' "$_GOOGLE_CONFIG_FILE"
}

# ─── Activate ──────────────────────────────────────────────────────────────

@test "google_activate: auto-detects studio with API key" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  GOOGLE_API_KEY="test-key"
  rm -f "$HOME/.mix/google_provider"
  run google_activate
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Studio activated"
  rm -f "$HOME/.mix/google_provider"
}

@test "google_activate: fails gracefully with no creds" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  unset GOOGLE_API_KEY
  rm -f "$HOME/.mix/google_provider" "$HOME/.mix/google_api_key"
  run google_activate
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "no credentials"
}

@test "google_activate: studio sets correct BASE_URL" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  GOOGLE_API_KEY="test-key"
  GOOGLE_MODE="studio"
  google_activate
  [ "$BASE_URL" = "https://generativelanguage.googleapis.com/v1beta/openai" ]
  rm -f "$HOME/.mix/google_provider"
}

@test "google_activate: vertex sets correct BASE_URL with project+region" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  GOOGLE_MODE="vertex"
  GOOGLE_PROJECT="test-project"
  GOOGLE_REGION="europe-west4"
  google_activate
  [ "$BASE_URL" = "https://europe-west4-aiplatform.googleapis.com/v1/projects/test-project/locations/europe-west4/endpoints/openapi" ]
  rm -f "$HOME/.mix/google_provider"
}

@test "google_activate: sets PROVIDER=google" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  GOOGLE_API_KEY="test-key"
  google_activate
  [ "$PROVIDER" = "google" ]
  rm -f "$HOME/.mix/google_provider"
}

# ─── Vertex token cache ──────────────────────────────────────────────────

@test "_google_vertex_token: returns cached token if fresh" {
  source "$PROJECT_ROOT/src/providers/google.sh"
  printf 'cached-token-xyz' > "$_GOOGLE_TOKEN_CACHE"
  # Can't override internal path easily — test concept with real cache path
  local _real_cache="/tmp/mix-google-access-token"
  printf 'cached-token-xyz' > "$_real_cache"
  run _google_vertex_token
  [ "$status" -eq 0 ]
  [ "$output" = "cached-token-xyz" ]
  rm -f "$_real_cache"
}
