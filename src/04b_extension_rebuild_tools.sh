_ext_rebuild_tools() {
  # Save base tools on first run
  if [ -z "${_TOOLS_JSON_BASE:-}" ]; then
    _TOOLS_JSON_BASE="$TOOLS_JSON"
  fi
  local _new_json="${_TOOLS_JSON_BASE%]}"
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    if type "${_ext}_tool_schema" >/dev/null 2>&1; then
      local _schema
      _schema=$(${_ext}_tool_schema 2>/dev/null)
      if [ -n "$_schema" ]; then
        _new_json="${_new_json}, ${_schema}"
      fi
    fi
  done
  _new_json="${_new_json}]"
  TOOLS_JSON="$_new_json"
}