# ─── Extension System ────────────────────────────────────────────────────────
# Drop-in extensions from ~/.mix/extensions/ and .mix/extensions/
# Like pi.dev: customize the harness, not your workflow.
#
# Convention-based hooks an extension can define:
#   <name>_init()           — called on load (set variables, register state)
#   <name>_cmd()            — REPL command handler (receives full input line)
#   <name>_tool()           — custom tool handler (receives name + json args)
#   <name>_on_edit()        — hook after successful edit_file (receives path)
#   <name>_on_create()      — hook after successful create_file (receives path)
#   <name>_on_bash()        — hook after bash execution (receives command)
#   <name>_on_session()     — hook for session save/restore
#   <name>_on_shutdown()    — cleanup on exit
#
# Extension files: ~/.mix/extensions/<name>.sh or .mix/extensions/<name>.sh
# Priority: project (.mix/) > global (~/.mix/) — project wins.

_MIX_EXTENSIONS_DIR="${HOME}/.mix/extensions"
_MIX_EXTENSIONS_LOCAL="${WORKDIR}/.mix/extensions"
_MIX_EXTENSIONS_LOADED=""

# ─── Load all extensions ────────────────────────────────────────────────────
_ext_load_all() {
  local _loaded=0
  # Build list: global first, then project (project overwrites global)
  local -A _ext_files
  if [ -d "$_MIX_EXTENSIONS_DIR" ]; then
    for f in "$_MIX_EXTENSIONS_DIR"/*.sh; do
      [ -f "$f" ] && _ext_files[$(basename "$f")]="$f"
    done
  fi
  if [ -d "$_MIX_EXTENSIONS_LOCAL" ]; then
    for f in "$_MIX_EXTENSIONS_LOCAL"/*.sh; do
      [ -f "$f" ] && _ext_files[$(basename "$f")]="$f"
    done
  fi

  for _name in "${!_ext_files[@]}"; do
    local _base="${_name%.sh}"
    source "${_ext_files[$_name]}" 2>/dev/null || {
      echo -e "  \033[1;31m$I_FAIL Extension $_name failed to load\033[0m" >&2
      continue
    }
    # Call init hook if defined
    if type "${_base}_init" >/dev/null 2>&1; then
      ${_base}_init 2>/dev/null || true
    fi
    _MIX_EXTENSIONS_LOADED+="$_base "
    _loaded=$((_loaded + 1))
  done

  # Trim trailing space
  _MIX_EXTENSIONS_LOADED="${_MIX_EXTENSIONS_LOADED% }"
  return 0
}

# ─── Dispatch command to extensions ─────────────────────────────────────────
# Returns 0 if an extension handled it, 1 if none did
_ext_dispatch_cmd() {
  local _input="$1"
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if type "${_ext}_cmd" >/dev/null 2>&1; then
      if ${_ext}_cmd "$_input"; then
        return 0
      fi
    fi
  done
  return 1
}

# ─── Dispatch tool to extensions ────────────────────────────────────────────
# Returns tool result string if handled, empty if none did
_ext_dispatch_tool() {
  local _tname="$1" _targs="$2"
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if type "${_ext}_tool" >/dev/null 2>&1; then
      local _result
      _result=$(${_ext}_tool "$_tname" "$_targs" 2>/dev/null) || continue
      if [ -n "$_result" ]; then
        printf '%s' "$_result"
        return 0
      fi
    fi
  done
  return 1
}

# ─── Dispatch hook to all extensions ────────────────────────────────────────
_ext_hook() {
  local _hook="$1"; shift
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if type "${_ext}_${_hook}" >/dev/null 2>&1; then
      ${_ext}_${_hook} "$@" 2>/dev/null || true
    fi
  done
}

# ─── List available extensions ──────────────────────────────────────────────
_ext_list() {
  local -A _seen
  # Loaded extensions
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    echo -e "  \033[38;5;82m●\033[0m $_ext \033[0;90m(loaded)\033[0m"
    _seen[$_ext]=1
  done
  # Available but not loaded
  for _dir in "$_MIX_EXTENSIONS_DIR" "$_MIX_EXTENSIONS_LOCAL"; do
    [ -d "$_dir" ] || continue
    for f in "$_dir"/*.sh; do
      [ -f "$f" ] || continue
      local _base="$(basename "$f" .sh)"
      [ -z "${_seen[$_base]:-}" ] && echo -e "    $_base \033[0;90m($f)\033[0m" && _seen[$_base]=1
    done
  done
}

# ─── Load single extension by name ─────────────────────────────────────────
_ext_load_one() {
  local _name="$1"
  # Already loaded?
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    [ "$_ext" = "$_name" ] && echo "  Extension $_name already loaded." && return 0
  done
  local _found=""
  # Project wins over global
  if [ -f "$_MIX_EXTENSIONS_LOCAL/${_name}.sh" ]; then
    _found="$_MIX_EXTENSIONS_LOCAL/${_name}.sh"
  elif [ -f "$_MIX_EXTENSIONS_DIR/${_name}.sh" ]; then
    _found="$_MIX_EXTENSIONS_DIR/${_name}.sh"
  fi
  [ -z "$_found" ] && echo "  Extension not found: $_name" && return 1

  source "$_found" 2>/dev/null || { echo "  Failed to load $_name"; return 1; }
  if type "${_name}_init" >/dev/null 2>&1; then
    ${_name}_init 2>/dev/null || true
  fi
  _MIX_EXTENSIONS_LOADED+="$_name "
  echo -e "  \033[38;5;82m$I_OK\033[0m Extension $_name loaded"
  return 0
}

# ─── Unload extension ──────────────────────────────────────────────────────
_ext_unload() {
  local _name="$1"
  local _new=""
  local _found=false
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if [ "$_ext" = "$_name" ]; then
      _found=true
      # Shutdown hook
      if type "${_name}_on_shutdown" >/dev/null 2>&1; then
        ${_name}_on_shutdown 2>/dev/null || true
      fi
      # Unset all functions
      for _fn in init cmd tool on_edit on_create on_bash on_session on_shutdown; do
        unset -f "${_name}_${_fn}" 2>/dev/null || true
      done
    else
      _new+="$_ext "
    fi
  done
  _MIX_EXTENSIONS_LOADED="${_new% }"
  if [ "$_found" = true ]; then
    echo -e "  \033[0;90mExtension $_name unloaded\033[0m"
  else
    echo "  Extension $_name not loaded"
  fi
}

# ─── Create example extension ──────────────────────────────────────────────
_ext_create() {
  local _name="$1"
  [ -z "$_name" ] && { echo "  Usage: /ext create <name>"; return 1; }
  local _target="$_MIX_EXTENSIONS_DIR/${_name}.sh"
  [ -f "$_target" ] && { echo "  $_target already exists"; return 1; }
  mkdir -p "$_MIX_EXTENSIONS_DIR"
  cat > "$_target" << 'EXAMPLE'
# ─── Extension: example ─────────────────────────────────────────────────────
# Hooks available:
#   <name>_init()           — called on load
#   <name>_cmd()            — REPL command (return 0=handled, 1=pass)
#   <name>_tool()           — custom tool (return result string or empty)
#   <name>_on_edit()        — hook after edit_file (receives path)
#   <name>_on_create()      — hook after create_file (receives path)
#   <name>_on_bash()        — hook after bash execution (receives command)
#   <name>_on_session()     — hook for session save/restore
#   <name>_on_shutdown()    — cleanup on exit

EXAMPLE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

example_init() {
  # Called when extension loads
  : # placeholder
}

example_cmd() {
  # Handle /example REPL command. Return 0 = handled, 1 = not handled.
  case "$1" in
    /example)
      echo "  Hello from $EXAMPLE_NAME extension!"
      return 0
      ;;
    /example\ *)
      local _arg="${1#/example }"
      echo "  Example got: $_arg"
      return 0
      ;;
  esac
  return 1  # not our command
}

example_on_edit() {
  # Called after successful edit_file
  local _path="$1"
  : # e.g. trigger lint, notify, etc
}

example_on_shutdown() {
  # Cleanup
  :
}
EXAMPLE
  # Replace placeholder name with actual
  sed -i "s/example/${_name}/g; s/EXAMPLE_NAME/${_name^^}_NAME/" "$_target"
  echo -e "  \033[38;5;82m$I_OK\033[0m Created $_target"
  echo "  Edit it, then /ext load $_name to activate."
}

# ─── Reload all extensions ──────────────────────────────────────────────────
_ext_reload() {
  # Shutdown all loaded
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if type "${_ext}_on_shutdown" >/dev/null 2>&1; then
      ${_ext}_on_shutdown 2>/dev/null || true
    fi
  done
  _MIX_EXTENSIONS_LOADED=""
  _ext_load_all
  local _count=0
  for _ in $_MIX_EXTENSIONS_LOADED; do _count=$((_count+1)); done
  echo -e "  \033[38;5;82m$I_OK\033[0m Reloaded $_count extensions"
}

# Load on source
_ext_load_all
