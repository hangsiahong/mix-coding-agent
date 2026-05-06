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
_FILE_CACHE_VALID_TIME=0  # epoch of last validation
_FILE_CACHE_VALID_TTL=30  # re-validate every 30s

# Initialize cache from empty
[ -z "$_FILE_CACHE" ] && _FILE_CACHE='{}'

# Add or update a file in the cache
file_cache_put() {
  local _fp="$1" _fc="$2"
  local _fmtime
  _fmtime=$(_mix_stat_mtime "$_fp")
  local _flines
  _flines=$(printf '%s' "$_fc" | wc -l)

  # Write content to temp file, pass cache + path + temp via argv
  local _ctmp; _ctmp=$(mktemp -t mix-$$-fc-XXXXXX)
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
  _FILE_CACHE_ORDER=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | grep -vF "$_fp" | grep -v '^$' | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
  _FILE_CACHE_ORDER="${_FILE_CACHE_ORDER:+$_FILE_CACHE_ORDER }$_fp"
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
  _FILE_CACHE_ORDER=$(printf '%s' "$_FILE_CACHE_ORDER" | tr ' ' '\n' | grep -vF "$_fp" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
}

# Validate cache entries — remove stale (externally modified) files
# Throttled: only re-validate every _FILE_CACHE_VALID_TTL seconds
file_cache_validate() {
  local _now; _now=$(date +%s 2>/dev/null || echo 0)
  local _vage=$(( _now - _FILE_CACHE_VALID_TIME ))
  [ "$_vage" -lt "$_FILE_CACHE_VALID_TTL" ] && return

  _FILE_CACHE_VALID_TIME=$_now
  _FILE_CACHE=$(python3 -c '
import json,sys,os
cache = json.loads(sys.argv[1])
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
' "$_FILE_CACHE" 2>/dev/null) || _FILE_CACHE='{}'

  # Rebuild order from cache keys, preserving original order
  local _new_order=""
  for _fp in $_FILE_CACHE_ORDER; do
    [ -z "$_fp" ] && continue
    # Check if key still exists in cache — use grep on JSON string
    if printf '%s' "$_FILE_CACHE" | grep -qF "\"$_fp\""; then
      _new_order="$_new_order $_fp"
    fi
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

  # Get ordered paths from cache (most recent first via reversed order)
  local _ordered_paths
  _ordered_paths=$(printf '%s\n' "$_FILE_CACHE_ORDER" | tr -s ' ' '\n' | sed '/^$/d' | tac | tr '\n' '|')

  # Build context via single python3 call (avoids repeated json parsing)
  printf '%s' "$_FILE_CACHE" | python3 -c '
import json,sys
cache = json.loads(sys.stdin.read())
order_str = sys.argv[1]
budget = int(sys.argv[2])
max_files = int(sys.argv[3])
per_file = int(sys.argv[4])

paths = [p for p in order_str.split("|") if p and p in cache]
result_parts = []
total_len = 0

for path in paths[:max_files]:
    entry = cache[path]
    content = entry["content"]
    nlines = entry.get("lines", "?")

    # Truncate content to per-file budget
    if len(content) > per_file:
        keep = per_file - 50
        head_n = int(keep * 0.7)
        content = content[:head_n] + "\n... (truncated) ...\n" + content[-(keep - head_n):]

    block = f"{path} ({nlines} lines):\n```\n{content}\n```"
    if total_len + len(block) + 2 > budget:
        break
    result_parts.append(block)
    total_len += len(block) + 2

if result_parts:
    print("## CACHED FILES (recently read — use instead of re-reading)\n")
    print("\n\n".join(result_parts))
' "$_ordered_paths" "$_budget" "$_max_files" "$_per_file" 2>/dev/null
}
