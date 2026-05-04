#!/usr/bin/env bats
# Tests for file_cache_put/del/validate/build_file_context — src/11a_file_cache.sh
# Stateful: functions modify global _FILE_CACHE and _FILE_CACHE_ORDER

setup() {
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    # Reset cache state before each test
    _FILE_CACHE='{}'
    _FILE_CACHE_ORDER=""
    source "$PROJECT_ROOT/src/11a_file_cache.sh"
}

# ── file_cache_put ───────────────────────────────────────────────────────────

@test "file_cache_put stores file content in cache" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "hello world" > "$_tmpfile"

    file_cache_put "$_tmpfile" "hello world"

    # Cache should now contain the file
    [[ "$_FILE_CACHE" == *"$_tmpfile"* ]]
    [[ "$_FILE_CACHE" == *"hello world"* ]]

    rm -f "$_tmpfile"
}

@test "file_cache_put adds file to access order" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "test content" > "$_tmpfile"

    file_cache_put "$_tmpfile" "test content"
    [[ "$_FILE_CACHE_ORDER" == *"$_tmpfile"* ]]

    rm -f "$_tmpfile"
}

@test "file_cache_put updates existing entry (re-put)" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "version 1" > "$_tmpfile"

    file_cache_put "$_tmpfile" "version 1"
    file_cache_put "$_tmpfile" "version 2"

    # Should have the updated content
    [[ "$_FILE_CACHE" == *"version 2"* ]]
    # Should not duplicate the order entry
    local count
    count=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | grep -cF "$_tmpfile")
    [ "$count" -eq 1 ]

    rm -f "$_tmpfile"
}

@test "file_cache_put tracks multiple files" {
    local _f1 _f2
    _f1=$(mktemp)
    _f2=$(mktemp)
    echo "file one" > "$_f1"
    echo "file two" > "$_f2"

    file_cache_put "$_f1" "file one"
    file_cache_put "$_f2" "file two"

    [[ "$_FILE_CACHE" == *"file one"* ]]
    [[ "$_FILE_CACHE" == *"file two"* ]]
    [[ "$_FILE_CACHE_ORDER" == *"$_f1"* ]]
    [[ "$_FILE_CACHE_ORDER" == *"$_f2"* ]]

    rm -f "$_f1" "$_f2"
}

# ── file_cache_del ───────────────────────────────────────────────────────────

@test "file_cache_del removes file from cache" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "to delete" > "$_tmpfile"

    file_cache_put "$_tmpfile" "to delete"
    [[ "$_FILE_CACHE" == *"to delete"* ]]

    file_cache_del "$_tmpfile"
    [[ "$_FILE_CACHE" != *"to delete"* ]]
    [[ "$_FILE_CACHE_ORDER" != *"$_tmpfile"* ]]

    rm -f "$_tmpfile"
}

@test "file_cache_del on non-existent entry is safe" {
    run file_cache_del "/tmp/nonexistent_cache_entry_12345"
    [ "$status" -eq 0 ]
}

@test "file_cache_del removes only target, keeps others" {
    local _f1 _f2
    _f1=$(mktemp)
    _f2=$(mktemp)
    echo "keep this" > "$_f1"
    echo "delete this" > "$_f2"

    file_cache_put "$_f1" "keep this"
    file_cache_put "$_f2" "delete this"

    file_cache_del "$_f2"

    [[ "$_FILE_CACHE" == *"keep this"* ]]
    [[ "$_FILE_CACHE" != *"delete this"* ]]

    rm -f "$_f1" "$_f2"
}

# ── file_cache_validate ─────────────────────────────────────────────────────

@test "file_cache_validate removes deleted files from cache" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "temp content" > "$_tmpfile"

    file_cache_put "$_tmpfile" "temp content"
    rm -f "$_tmpfile"

    file_cache_validate
    [[ "$_FILE_CACHE" != *"temp content"* ]]
}

@test "file_cache_validate keeps existing files" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "still here" > "$_tmpfile"

    file_cache_put "$_tmpfile" "still here"
    file_cache_validate

    [[ "$_FILE_CACHE" == *"still here"* ]]

    rm -f "$_tmpfile"
}

@test "file_cache_validate removes externally modified files" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "original" > "$_tmpfile"

    file_cache_put "$_tmpfile" "original"

    # Modify the file externally (change mtime)
    sleep 1
    echo "modified externally" > "$_tmpfile"

    file_cache_validate

    # Should be evicted because mtime changed
    [[ "$_FILE_CACHE" != *"original"* ]]

    rm -f "$_tmpfile"
}

# ── build_file_context ───────────────────────────────────────────────────────

@test "build_file_context returns empty when cache is empty" {
    run build_file_context
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "build_file_context returns content for cached files" {
    local _tmpfile
    _tmpfile=$(mktemp)
    echo "cached file content here" > "$_tmpfile"

    file_cache_put "$_tmpfile" "cached file content here"

    run build_file_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"cached file content here"* ]]
    [[ "$output" == *"CACHED FILES"* ]]

    rm -f "$_tmpfile"
}

@test "build_file_context truncates large files" {
    local _tmpfile
    _tmpfile=$(mktemp)
    local large_content
    large_content=$(printf '%0.sX' {1..500})
    echo "$large_content" > "$_tmpfile"

    file_cache_put "$_tmpfile" "$large_content"

    run build_file_context
    [ "$status" -eq 0 ]
    # Should be truncated, not the full 500 chars
    [ ${#output} -lt ${#large_content} ]
    [[ "$output" == *"truncated"* ]]

    rm -f "$_tmpfile"
}
