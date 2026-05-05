#!/usr/bin/env bash
# ─── Extension: fetcher ──────────────────────────────────────────────────────
# Description: Fetches URLs and converts HTML to Markdown/Text
# Enables the /fetch command and fetch_url tool.

FETCHER_NAME="fetcher"

fetcher_init() {
  true # Initialize anything here if needed
}

fetcher_cmd() {
  case "$1" in
    /fetch)
      echo "  Usage: /fetch <url>"
      return 0
      ;;
    /fetch\ *)
      local _url="${1#/fetch }"
      echo "  Fetching $_url ..."
      _fetcher_internal_fetch "$_url"
      return 0
      ;;
  esac
  return 1
}

fetcher_tool_schema() {
  cat << 'EOF'
{
  "type": "function",
  "function": {
    "name": "fetch_url",
    "description": "Fetch a webpage and return its readable text content. Useful for reading docs, PRs, or issues.",
    "parameters": {
      "type": "object",
      "properties": {
        "url": { "type": "string", "description": "The full HTTP/HTTPS URL to fetch" }
      },
      "required": ["url"]
    }
  }
}
EOF
}

fetcher_tool() {
  local _tname="$1"
  local _targs="$2"
  
  if [ "$_tname" = "fetch_url" ]; then
    # Extract url from json args using python
    local _url
    _url=$(echo "$_targs" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url', ''))" 2>/dev/null)
    if [ -z "$_url" ]; then
      echo "[fetch_url] Error: URL not provided."
      return 0
    fi
    echo "[fetch_url] Fetching $_url" >&2
    _fetcher_internal_fetch "$_url"
    return 0
  fi
  return 1
}

_fetcher_internal_fetch() {
  local _url="$1"
  python3 -c "
import urllib.request, re, sys
try:
    req = urllib.request.Request('$_url', headers={'User-Agent': 'Mozilla/5.0 (compatible; MixBot/1.0)'})
    html = urllib.request.urlopen(req, timeout=15).read().decode('utf-8', errors='ignore')
    # Basic cleanup
    html = re.sub(r'<script[\s\S]*?</script>', '', html, flags=re.I)
    html = re.sub(r'<style[\s\S]*?</style>', '', html, flags=re.I)
    html = re.sub(r'<nav[\s\S]*?</nav>', '', html, flags=re.I)
    html = re.sub(r'<header[\s\S]*?</header>', '', html, flags=re.I)
    html = re.sub(r'<footer[\s\S]*?</footer>', '', html, flags=re.I)
    text = re.sub(r'<[^>]+>', ' ', html)
    text = re.sub(r'\s+', ' ', text).strip()
    # Chunking: return up to 15k chars to prevent blowing up the context window
    print(text[:15000])
except Exception as e:
    print(f'Error fetching {sys.argv[1]}: {e}', file=sys.stderr)
" "$_url"
}
