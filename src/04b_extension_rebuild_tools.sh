_ext_rebuild_tools() {
  # Wait until base TOOLS_JSON is defined before caching it
  if [ -z "${TOOLS_JSON:-}" ]; then
    return 0
  fi

  # Save base tools on first run
  if [ -z "${_TOOLS_JSON_BASE:-}" ]; then
    _TOOLS_JSON_BASE="$TOOLS_JSON"
  fi
  
  local _base_content="${_TOOLS_JSON_BASE#\[}"
  _base_content="${_base_content%\]}"
  
  local _new_json="["
  [ -n "${_base_content//[[:space:]]/}" ] && _new_json+="$_base_content"
  
  local _first=true
  [ -n "${_base_content//[[:space:]]/}" ] && _first=false
  
  local _seen=""
  for _ext in $_MIX_EXTENSIONS_LOADED; do
    [[ " $_seen " =~ " $_ext " ]] && continue
    _seen+="$_ext "
    
    if type "${_ext}_tool_schema" >/dev/null 2>&1; then
      local _schema
      _schema=$(${_ext}_tool_schema 2>/dev/null | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)))' 2>/dev/null)
      if [ -n "$_schema" ]; then
        if [ "$_first" = false ]; then
          _new_json+=","
        fi
        _new_json+="$_schema"
        _first=false
      fi
    fi
  done
  _new_json+="]"
  TOOLS_JSON="$_new_json"
}