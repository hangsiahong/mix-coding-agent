# ─── File Content Cache ──────────────────────────────────────────────────────
# Session-scoped file content cache. Survives history compaction.
# Purpose: eliminate re-reading files the agent already saw.
# After compact, model loses file contents from history but cache persists.
#
# How it works:
#   1. Every read_file call → cache stores content + mtime
#   2. Every edit_file/create_file → cache updates with new content
#   3. build_file_context() → injects top-N recently-accessed files into system prompt
#   4. Cache invalidates on mtime change (file edited externally)
#
# Budget: ~3000 chars (~1000 tokens). Max 8 files, 400 chars each.
# This leaves room in system prompt alongside repo map (~4800 chars).

_FILE_CACHE=""        # JSON: {"path": {"content": "...", "mtime": 123, "atime": 456, "lines": 42}}
_FILE_CACHE_ORDER=""  # "path1 path2 path3" — access order (most recent last)

# Initialize cache from empty
[ -z "$_FILE_CACHE" ] && _FILE_CACHE='{}'

# Add or update a file in the cache
file_cache_put() {
  local _fp="$1" _fc="$2"
  local _fmtime
  _fmtime=$(stat -c '%Y' "$_fp" 2>/dev/null || echo "0")
  local _flines
  _flines=$(printf '%s' "$_fc" | wc -l)

  # Write content to temp file, pass cache + path + temp via argv
  local _ctmp; _ctmp=$(mktemp -t mix-fc-XXXXXX)
  printf '%s' "$_fc" > "$_ctmp"

  _FILE_CACHE=$(python3 -c '
import json,sys,os,time
cache = json.loads(sys.argv[1])
path = sys.argv[2]
content = open(sys.argv[3]).read()
mtime = int(sys.argv[4])
nlines = int(sys.argv[5])
cache[path] = {"content": content, "mtime": mtime, "atime": time.time(), "lines": nlines}
print(json.dumps(cache))
' "$_FILE_CACHE" "$_fp" "$_ctmp" "$_fmtime" "$_flines" 2>/dev/null) || { rm -f "$_ctmp"; return; }
  rm -f "$_ctmp"

  # Update access order: remove existing entry, append to end
  _FILE_CACHE_ORDER=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | grep -vF "$_fp" | tr '\n' ' ' | sed 's/^ *//')
  _FILE_CACHE_ORDER="$_FILE_CACHE_ORDER $_fp"
  _FILE_CACHE_ORDER="${_FILE_CACHE_ORDER# }"
}

# Remove a file from cache
file_cache_del() {
  local _fp="$1"
  _FILE_CACHE=$(python3 -c '
import json,sys
cache = json.loads(sys.argv[1])
cache.pop(sys.argv[2], None)
print(json.dumps(cache))
' "$_FILE_CACHE" "$_fp" 2>/dev/null) || return
  _FILE_CACHE_ORDER=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | grep -vF "$_fp" | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
}

# Validate cache entries — remove stale (externally modified) files
file_cache_validate() {
  _FILE_CACHE=$(printf '%s' "$_FILE_CACHE" | python3 -c '
import json,sys,os
cache = json.loads(sys.stdin.read())
stale = []
for path, entry in cache.items():
    if not os.path.exists(path):
        stale.append(path)
        continue
    try:
        mt = int(os.path.getmtime(path))
        if mt != entry.get("mtime", 0):
            stale.append(path)
    except:
        stale.append(path)
for s in stale:
    del cache[s]
print(json.dumps(cache))
' 2>/dev/null) || _FILE_CACHE='{}'

  # Remove stale entries from order too
  local _new_order=""
  for _fp in $_FILE_CACHE_ORDER; do
    printf '%s' "$_FILE_CACHE" | python3 -c "
import json,sys
cache = json.loads(sys.stdin.read())
sys.exit(0 if '$_fp' in cache else 1)
" 2>/dev/null && _new_order="$_new_order $_fp"
  done
  _FILE_CACHE_ORDER="${_new_order# }"
}

# Build file context string for system prompt injection
# Returns top-N most recently accessed files, truncated to budget
build_file_context() {
  file_cache_validate

  # Count cached files
  local _nfiles
  _nfiles=$(printf '%s' "$_FILE_CACHE" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null) || _nfiles=0
  [ "$_nfiles" -eq 0 ] && return

  # Budget: 3000 chars total, max 8 files, 400 chars per file
  local _budget=3000 _max_files=8 _per_file=400

  # Get files in reverse access order (most recent first)
  local _reversed
  _reversed=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | tac | tr '\n' ' ')

  local _result=""
  local _count=0
  for _fp in $_reversed; do
    [ "$_count" -ge "$_max_files" ] && break
    [ -z "$_fp" ] && continue

    local _entry
    _entry=$(printf '%s' "$_FILE_CACHE" | python3 -c "
import json,sys
cache = json.loads(sys.stdin.read())
entry = cache.get('$_fp', {})
content = entry.get('content', '')
lines = content.split('\n')
# Truncate to budget
if len(content) > $_per_file:
    # Keep first 70% and last 30%
    keep = $_per_file - 50  # room for truncation notice
    head_n = int(keep * 0.7)
    content = content[:head_n] + '\n... (truncated) ...\n' + content[-(keep - head_n):]
print(json.dumps({'content': content, 'lines': entry.get('lines', 0)}))
" 2>/dev/null) || continue

    local _content _lines
    _content=$(printf '%s' "$_entry" | python3 -c 'import json,sys;print(json.load(sys.stdin)["content"])' 2>/dev/null) || continue
    _lines=$(printf '%s' "$_entry" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("lines","?"))' 2>/dev/null) || _lines="?"

    local _block="$_fp ($_lines lines):
\`\`\`
$_content
\`\`\`"

    # Check budget
    local _new_len
    _new_len=$(( ${#_result} + ${#_block} + 2 ))
    [ "$_new_len" -gt "$_budget" ] && break

    _result="$_result

$_block"
    _count=$(( _count + 1 ))
  done

  [ -n "$_result" ] && printf '## CACHED FILES (recently read — use instead of re-reading)
%s' "$_result"
}
