# ─── Environment Detection ──────────────────────────────────────────
detect_env() {
  local info=""
  GIT_ENABLED=false; TEST_CMD=""
  if git -C "$WORKDIR" rev-parse --is-inside-work-tree 2>/dev/null | grep -q true; then
    GIT_ENABLED=true
    local _br; _br=$(git -C "$WORKDIR" branch --show-current 2>/dev/null || echo "?")
    info+=" git:$_br"
  fi
  [ -f "$WORKDIR/package.json" ]   && info+=" node"
  [ -f "$WORKDIR/go.mod" ]         && info+=" go"
  [ -f "$WORKDIR/Cargo.toml" ]     && info+=" rust"
  { [ -f "$WORKDIR/requirements.txt" ] || [ -f "$WORKDIR/pyproject.toml" ] \
    || [ -f "$WORKDIR/setup.py" ]; }   && info+=" python"
  { [ -f "$WORKDIR/Dockerfile" ] || [ -f "$WORKDIR/docker-compose.yml" ] \
    || [ -f "$WORKDIR/docker-compose.yaml" ]; } && info+=" docker"
  # Test runner detection
  if [ -f "$WORKDIR/package.json" ]; then
    local _pkgjson="$WORKDIR/package.json"
    if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if 'test' in d.get('scripts',{}) else 1)" "$_pkgjson" 2>/dev/null; then
      TEST_CMD="npm test"; info+=" tests(npm)"
    fi
  elif [ -f "$WORKDIR/pytest.ini" ] || [ -f "$WORKDIR/conftest.py" ] || [ -f "$WORKDIR/setup.cfg" ]; then
    TEST_CMD="pytest"; info+=" tests(pytest)"
  fi
  # Linter/tool detection (for auto-verify)
  command -v shellcheck >/dev/null 2>&1 && info+=" shellcheck"
  command -v ruff >/dev/null 2>&1 && info+=" ruff"
  command -v mypy >/dev/null 2>&1 && info+=" mypy"
  command -v ctags >/dev/null 2>&1 && {
    if ctags --version 2>/dev/null | grep -iq "Universal Ctags"; then
      info+=" ctags(universal)"
    fi
  }
  ENV_INFO="${info# }"  # trim leading space
}

detect_env

# Try loading previous session (sets _SESSION_AVAILABLE=true if found)
session_load 2>/dev/null
session_hint
