#!/usr/bin/env bats
# Tests for parse_resp() — src/17_response_parser.sh
# Pure function: takes JSON string → returns RAW/TC/TEXT lines

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    source "$PROJECT_ROOT/src/17_response_parser.sh"
}

# ── Tool calls ───────────────────────────────────────────────────────────────

@test "parse_resp extracts a single tool call" {
    local json='{"choices":[{"message":{"tool_calls":[{"id":"tc_001","function":{"name":"bash","arguments":"{\"command\":\"ls\"}"}}]}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    # Should contain RAW: line
    [[ "$output" == *"RAW:"* ]]
    # Should contain TC: line with tool call details
    [[ "$output" == *"TC:tc_001|||bash|||"* ]]
}

@test "parse_resp extracts multiple tool calls" {
    local json='{"choices":[{"message":{"tool_calls":[{"id":"tc_001","function":{"name":"bash","arguments":"{\"command\":\"ls\"}"}},{"id":"tc_002","function":{"name":"read_file","arguments":"{\"path\":\"/tmp/test\"}"}}]}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TC:tc_001|||bash|||"* ]]
    [[ "$output" == *"TC:tc_002|||read_file|||"* ]]
}

@test "parse_resp includes tool call arguments" {
    local json='{"choices":[{"message":{"tool_calls":[{"id":"tc_1","function":{"name":"edit_file","arguments":"{\"path\":\"/foo.sh\",\"old_text\":\"old\",\"new_text\":\"new\"}"}}]}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"edit_file|||"* ]]
    [[ "$output" == *"/foo.sh"* ]]
}

# ── Plain text response ─────────────────────────────────────────────────────

@test "parse_resp extracts plain text response" {
    local json='{"choices":[{"message":{"content":"Here is the answer to your question."}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEXT:Here is the answer to your question."* ]]
}

@test "parse_resp returns TEXT for response with no tool calls" {
    local json='{"choices":[{"message":{"content":"Done.","tool_calls":null}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEXT:Done."* ]]
}

@test "parse_resp handles empty content as TEXT:(empty)" {
    local json='{"choices":[{"message":{"content":""}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEXT:(empty)"* ]]
}

# ── RAW base64 output ────────────────────────────────────────────────────────

@test "parse_resp always includes RAW line with base64 encoded message" {
    local json='{"choices":[{"message":{"content":"hello"}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RAW:"* ]]
    # RAW value should be valid base64 (no spaces, only base64 chars)
    local raw_line
    raw_line=$(printf '%s' "$output" | grep '^RAW:' | head -1)
    raw_line="${raw_line#RAW:}"
    [ -n "$raw_line" ]
    # Base64 decode should succeed
    printf '%s' "$raw_line" | base64 -d >/dev/null 2>&1
}

@test "parse_resp RAW decodes to valid JSON with message fields" {
    local json='{"choices":[{"message":{"content":"test content"}}]}'
    run parse_resp "$json"
    [ "$status" -eq 0 ]
    local raw_line
    raw_line=$(printf '%s' "$output" | grep '^RAW:' | head -1)
    raw_line="${raw_line#RAW:}"
    local decoded
    decoded=$(printf '%s' "$raw_line" | base64 -d 2>/dev/null)
    # Decoded should be valid JSON
    printf '%s' "$decoded" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
}

# ── Error handling ───────────────────────────────────────────────────────────

@test "parse_resp returns FAIL for invalid JSON" {
    run parse_resp "not json at all"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL:parse"* ]]
}

@test "parse_resp returns FAIL for empty input" {
    run parse_resp ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL:parse"* ]]
}

@test "parse_resp returns FAIL for malformed JSON structure" {
    run parse_resp '{"choices":[]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL:parse"* ]]
}
