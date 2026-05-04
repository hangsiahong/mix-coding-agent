# ─── Repo Map (codebase structural awareness) ────────────────────────────────
# Generates a compressed map of the codebase injected into the system prompt.
# Eliminates 2-3 "orientation" tool calls per task — agent knows file layout,
# function signatures, and class structure without reading files.
#
# Strategy: regex-based extraction. No tree-sitter, no deps, no pip.
# Gets 80% of Aider's repo-map value for 5% of the code.

_REPO_MAP=""
_REPO_MAP_MTIMES=""   # "file:mtime:file:mtime:..." for invalidation
_REPO_MAP_TIME=0      # epoch seconds when map was built
_REPO_MAP_TTL=600     # rebuild every 10 minutes

# Patterns per language — extract structural lines
# Each: "extension:pattern:label"
_REPO_MAP_PATTERNS=(
  "sh:^[a-zA-Z_][a-zA-Z0-9_]*\(\):fn"
  "sh:^  [a-zA-Z_][a-zA-Z0-9_]*\(\):fn"
  "py:^(def |class |    def ):def"
  "py:^(import |from ):import"
  "js:^(export (default )?(function |class |async function )):decl"
  "js:^(function |class ):decl"
  "js:^(export (const|let) [A-Z][a-zA-Z]+ =):decl"
  "js:^(interface |type [A-Z]):decl"
  "ts:^(export (default )?(function |class |async function )):decl"
  "ts:^(function |class ):decl"
  "ts:^(export (const|let) [A-Z][a-zA-Z]+ =):decl"
  "ts:^(interface |type [A-Z]|enum [A-Z]):decl"
  "ts:^(export (async )?(function |const) (GET|POST|PUT|DELETE|PATCH)):api"
  "go:^(func |type |var |const |import ):decl"
  "rs:^(pub )?(fn |struct |enum |trait |impl |mod ):decl"
  "java:^(public |private |protected |static ).*(class |interface |void |int |String ):decl"
  "rb:^(def |class |module ):decl"
  "c:^(void |int |char |static |struct ):decl"
  "h:^(void |int |char |static |struct |#define |typedef ):decl"
)

# Directories to always skip
_REPO_MAP_SKIP_DIRS=(
  .git node_modules __pycache__ .venv venv dist build .next
  .nuxt target .gradle .idea .vscode .cache .tox .mypy_cache
  .pytest_cache coverage htmlcov .sass-cache bower_components
  vendor/bundle .mix .agent .terraform .terragrunt-cache
)

_build_skip_find() {
  local prune=""
  for d in "${_REPO_MAP_SKIP_DIRS[@]}"; do
    prune+="-path ./$d -prune -o "
  done
  printf '%s' "$prune"
}

# Build the repo map string
build_repo_map() {
  # Check cache validity
  local _now; _now=$(date +%s 2>/dev/null || echo 0)
  local _age=$(( _now - _REPO_MAP_TIME ))
  if [ -n "$_REPO_MAP" ] && [ "$_age" -lt "$_REPO_MAP_TTL" ] && _repo_map_files_unchanged; then
    printf '%s' "$_REPO_MAP"
    return
  fi

  local _map=""
  local _file_list
  _file_list=$(find . $(_build_skip_find) -type f \
    \( -name '*.sh' -o -name '*.py' -o -name '*.js' -o -name '*.ts' \
       -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' \
       -o -name '*.c' -o -name '*.h' -o -name '*.jsx' -o -name '*.tsx' \
       -o -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \
       -o -name '*.json' -o -name '*.sql' -o -name '*.proto' \) \
    -print 2>/dev/null | sort)

  if [ -z "$_file_list" ]; then
    _REPO_MAP=""
    printf ''
    return
  fi

  local _new_mtimes=""
  local _file_count=0
  local _token_budget=4500  # ~1500 tokens, at 3 chars/token
  local _chars_used=0

  # File tree: collapse directories, limit to 60 lines max
  local _tree_raw
  _tree_raw=$(printf '%s' "$_file_list" | sed 's|^\./||')
  local _tree_line_count; _tree_line_count=$(printf '%s' "$_tree_raw" | wc -l)

  if [ "$_tree_line_count" -gt 60 ]; then
    # Collapse: show directories with file counts, then individual files tail
    local _dirs
    _dirs=$(printf '%s' "$_tree_raw" | sed 's|/[^/]*$||' | sort -u | head -30)
    local _collapsed=""
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      local _cnt; _cnt=$(printf '%s' "$_tree_raw" | grep -c "^${d}/" 2>/dev/null || echo 1)
      _collapsed="${_collapsed}${d}/ (${_cnt} files)
"
    done <<< "$_dirs"
    # Append root-level files
    local _root_files
    _root_files=$(printf '%s' "$_tree_raw" | grep -v '/' | head -10)
    _map="${_collapsed}${_root_files}"
  else
    _map="$_tree_raw"
  fi
  _chars_used=${#_map}

  # Then structural extraction per file
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local _rel="${f#./}"

    # Track mtime for cache invalidation
    local _mt; _mt=$(stat -c '%Y' "$f" 2>/dev/null || echo 0)
    _new_mtimes="${_new_mtimes}${_rel}:${_mt}:"

    # Token budget check — stop if we're over
    [ "$_chars_used" -gt "$_token_budget" ] && break

    # Extract structure based on file extension
    local _ext="${_rel##*.}"
    local _struct=""
    local _lines; _lines=$(wc -l < "$f" 2>/dev/null || echo 0)

    # Skip very large files — just note the size
    if [ "$_lines" -gt 500 ]; then
      _struct="  ($_lines lines)"
    else
      local _pat=""
      for _pp in "${_REPO_MAP_PATTERNS[@]}"; do
        local _pext="${_pp%%:*}"; local _rest="${_pp#*:}"
        if [ "$_ext" = "$_pext" ]; then
          _pat="${_rest%%:*}"
          break
        fi
      done

      if [ -n "$_pat" ]; then
        _struct=$(grep -E "$_pat" "$f" 2>/dev/null | head -30 | sed 's/^/  /')
      fi
    fi

    if [ -n "$_struct" ]; then
      local _entry="${_rel}:${_lines}L
${_struct}
"
      _map="${_map}
${_entry}"
      _chars_used=$((_chars_used + ${#_entry}))
    fi

    _file_count=$((_file_count + 1))
  done <<< "$_file_list"

  # Git awareness: show recently changed files (if git enabled)
  if [ "$GIT_ENABLED" = true ]; then
    local _recent
    _recent=$(git -C "$WORKDIR" diff --name-only HEAD~5 2>/dev/null | head -20 || true)
    if [ -n "$_recent" ]; then
      _map="${_map}
── recently changed ──
${_recent}"
    fi
  fi

  _REPO_MAP="$_map"
  _REPO_MAP_MTIMES="$_new_mtimes"
  _REPO_MAP_TIME="$_now"
  printf '%s' "$_REPO_MAP"
}

# Check if tracked files have changed since last build
_repo_map_files_unchanged() {
  [ -z "$_REPO_MAP_MTIMES" ] && return 1
  local _old="$_REPO_MAP_MTIMES"
  local _changed=0

  # Sample check — don't check every file, just up to 50 random ones
  local _checked=0
  local _rest="$_old"
  while [ -n "$_rest" ] && [ "$_checked" -lt 50 ]; do
    local _entry="${_rest%%:*}"
    _rest="${_rest#*:}"
    local _mtime="${_rest%%:*}"
    _rest="${_rest#*:}"
    [ -z "$_entry" ] && continue
    local _cur; _cur=$(stat -c '%Y' "$_entry" 2>/dev/null || echo 0)
    [ "$_cur" != "$_mtime" ] && _changed=1 && break
    _checked=$((_checked + 1))
  done

  [ "$_changed" -eq 0 ]
}

# Force rebuild (useful after /refresh or major file changes)
repo_map_invalidate() {
  _REPO_MAP=""
  _REPO_MAP_MTIMES=""
  _REPO_MAP_TIME=0
}
