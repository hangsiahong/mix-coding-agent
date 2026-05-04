#!/usr/bin/env bats
# Tests for extension system (src/04b_extension_system.sh)

setup() {
  export HOME="$(mktemp -d)"
  export WORKDIR="$(mktemp -d)"
  export _MIX_EXTENSIONS_DIR="$HOME/.mix/extensions"
  export _MIX_EXTENSIONS_LOCAL="$WORKDIR/.mix/extensions"
  export _MIX_EXTENSIONS_LOADED=""
  mkdir -p "$_MIX_EXTENSIONS_DIR" "$_MIX_EXTENSIONS_LOCAL"
  source src/04b_extension_system.sh
}

teardown() {
  rm -rf "$WORKDIR" "$HOME"
}

# ─── _ext_load_all ──────────────────────────────────────────────────────────

@test "ext_load_all returns ok when no extensions dir" {
  rm -rf "$_MIX_EXTENSIONS_DIR" "$_MIX_EXTENSIONS_LOCAL"
  run _ext_load_all
  [ "$status" -eq 0 ]
}

@test "ext_load_all loads extension from global dir" {
  cat > "$_MIX_EXTENSIONS_DIR/testext.sh" << 'EOF'
testext_init() { TESTEXT_INIT=1; }
testext_cmd() { return 1; }
EOF
  _ext_load_all
  [[ "$_MIX_EXTENSIONS_LOADED" == *"testext"* ]]
  [ "$TESTEXT_INIT" = "1" ]
}

@test "ext_load_all loads extension from project dir" {
  cat > "$_MIX_EXTENSIONS_LOCAL/testext.sh" << 'EOF'
testext_init() { TESTEXT_INIT=project; }
testext_cmd() { return 1; }
EOF
  _ext_load_all
  [[ "$_MIX_EXTENSIONS_LOADED" == *"testext"* ]]
  [ "$TESTEXT_INIT" = "project" ]
}

@test "ext_load_all project overrides global" {
  cat > "$_MIX_EXTENSIONS_DIR/testext.sh" << 'EOF'
testext_init() { TESTEXT_VAL=global; }
EOF
  cat > "$_MIX_EXTENSIONS_LOCAL/testext.sh" << 'EOF'
testext_init() { TESTEXT_VAL=project; }
EOF
  _ext_load_all
  [ "$TESTEXT_VAL" = "project" ]
}

@test "ext_load_all skips broken extension gracefully" {
  cat > "$_MIX_EXTENSIONS_DIR/broken.sh" << 'EOF'
this is not valid bash syntax (
EOF
  cat > "$_MIX_EXTENSIONS_DIR/good.sh" << 'EOF'
good_init() { GOOD_INIT=1; }
EOF
  _ext_load_all
  [[ "$_MIX_EXTENSIONS_LOADED" != *"broken"* ]]
  [[ "$_MIX_EXTENSIONS_LOADED" == *"good"* ]]
}

# ─── _ext_dispatch_cmd ─────────────────────────────────────────────────────

@test "ext_dispatch_cmd returns 1 when no extensions" {
  _MIX_EXTENSIONS_LOADED=""
  run _ext_dispatch_cmd "/hello"
  [ "$status" -eq 1 ]
}

@test "ext_dispatch_cmd calls extension cmd handler" {
  cat > "$_MIX_EXTENSIONS_DIR/hello.sh" << 'EOF'
hello_cmd() {
  case "$1" in
    /hello) echo "world"; return 0 ;;
  esac
  return 1
}
EOF
  _ext_load_all
  run _ext_dispatch_cmd "/hello"
  [ "$status" -eq 0 ]
  [ "$output" = "world" ]
}

@test "ext_dispatch_cmd passes through unhandled commands" {
  cat > "$_MIX_EXTENSIONS_DIR/hello.sh" << 'EOF'
hello_cmd() {
  case "$1" in
    /hello) echo "world"; return 0 ;;
  esac
  return 1
}
EOF
  _ext_load_all
  run _ext_dispatch_cmd "/other"
  [ "$status" -eq 1 ]
}

# ─── _ext_dispatch_tool ────────────────────────────────────────────────────

@test "ext_dispatch_tool returns empty when no handler" {
  _MIX_EXTENSIONS_LOADED=""
  run _ext_dispatch_tool "mytool" '{"arg":"val"}'
  [ "$status" -eq 1 ]
}

@test "ext_dispatch_tool routes to extension tool handler" {
  cat > "$_MIX_EXTENSIONS_DIR/mytool.sh" << 'EOF'
mytool_tool() {
  local name="$1" args="$2"
  if [ "$name" = "mytool" ]; then
    echo "tool result: $args"
    return 0
  fi
  return 1
}
EOF
  _ext_load_all
  local result
  result=$(_ext_dispatch_tool "mytool" '{"key":"val"}')
  [[ "$result" == *"tool result"* ]]
}

# ─── _ext_hook ──────────────────────────────────────────────────────────────

@test "ext_hook calls all extension hooks" {
  cat > "$_MIX_EXTENSIONS_DIR/observer.sh" << 'EOF'
observer_on_edit() { EDIT_HOOK_PATH="$1"; }
observer_on_create() { CREATE_HOOK_PATH="$1"; }
EOF
  _ext_load_all
  _ext_hook on_edit "/tmp/test.sh"
  [ "$EDIT_HOOK_PATH" = "/tmp/test.sh" ]
  _ext_hook on_create "/tmp/new.sh"
  [ "$CREATE_HOOK_PATH" = "/tmp/new.sh" ]
}

@test "ext_hook is silent when no extensions loaded" {
  _MIX_EXTENSIONS_LOADED=""
  run _ext_hook on_edit "/tmp/test.sh"
  [ "$status" -eq 0 ]
}

# ─── _ext_load_one / _ext_unload ───────────────────────────────────────────

@test "ext_load_one loads specific extension" {
  cat > "$_MIX_EXTENSIONS_DIR/specific.sh" << 'EOF'
specific_init() { SPECIFIC_LOADED=1; }
EOF
  _MIX_EXTENSIONS_LOADED=""
  _ext_load_one "specific"
  [[ "$_MIX_EXTENSIONS_LOADED" == *"specific"* ]]
  [ "$SPECIFIC_LOADED" = "1" ]
}

@test "ext_load_one prefers project over global" {
  cat > "$_MIX_EXTENSIONS_DIR/specific.sh" << 'EOF'
specific_init() { SPECIFIC_SRC=global; }
EOF
  cat > "$_MIX_EXTENSIONS_LOCAL/specific.sh" << 'EOF'
specific_init() { SPECIFIC_SRC=project; }
EOF
  _ext_load_one "specific"
  [ "$SPECIFIC_SRC" = "project" ]
}

@test "ext_load_one reports already loaded" {
  cat > "$_MIX_EXTENSIONS_DIR/dup.sh" << 'EOF'
dup_init() { :; }
EOF
  _MIX_EXTENSIONS_LOADED="dup"
  run _ext_load_one "dup"
  [[ "$output" == *"already loaded"* ]]
}

@test "ext_load_one reports not found" {
  run _ext_load_one "nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "ext_unload removes extension and calls shutdown" {
  cat > "$_MIX_EXTENSIONS_DIR/removable.sh" << 'EOF'
removable_on_shutdown() { REMOVABLE_SHUTDOWN=1; }
removable_cmd() { return 1; }
EOF
  _ext_load_all
  [[ "$_MIX_EXTENSIONS_LOADED" == *"removable"* ]]
  _ext_unload "removable"
  [[ "$_MIX_EXTENSIONS_LOADED" != *"removable"* ]]
  [ "$REMOVABLE_SHUTDOWN" = "1" ]
}

@test "ext_unload reports not loaded" {
  _MIX_EXTENSIONS_LOADED=""
  run _ext_unload "ghost"
  [[ "$output" == *"not loaded"* ]]
}

# ─── _ext_list ──────────────────────────────────────────────────────────────

@test "ext_list shows loaded extensions" {
  cat > "$_MIX_EXTENSIONS_DIR/showcase.sh" << 'EOF'
showcase_init() { :; }
EOF
  _ext_load_all
  run _ext_list
  [[ "$output" == *"showcase"* ]]
  [[ "$output" == *"loaded"* ]]
}

@test "ext_list shows available but not loaded" {
  cat > "$_MIX_EXTENSIONS_DIR/available.sh" << 'EOF'
available_init() { :; }
EOF
  _MIX_EXTENSIONS_LOADED=""
  run _ext_list
  [[ "$output" == *"available"* ]]
  [[ "$output" != *"loaded"* ]]
}

# ─── _ext_create ────────────────────────────────────────────────────────────

@test "ext_create creates extension template" {
  _ext_create "myext"
  [ -f "$_MIX_EXTENSIONS_DIR/myext.sh" ]
  grep -q "myext_init" "$_MIX_EXTENSIONS_DIR/myext.sh"
  grep -q "myext_cmd" "$_MIX_EXTENSIONS_DIR/myext.sh"
}

@test "ext_create refuses to overwrite existing" {
  echo "existing" > "$_MIX_EXTENSIONS_DIR/existing.sh"
  run _ext_create "existing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "ext_create requires a name" {
  run _ext_create ""
  [ "$status" -eq 1 ]
}

# ─── _ext_reload ────────────────────────────────────────────────────────────

@test "ext_reload reinitializes all extensions" {
  cat > "$_MIX_EXTENSIONS_DIR/reloadable.sh" << 'EOF'
RELOAD_COUNT=${RELOAD_COUNT:-0}
RELOAD_COUNT=$((RELOAD_COUNT + 1))
reloadable_init() { RELOADED=$RELOAD_COUNT; }
EOF
  _ext_load_all
  [ "$RELOADED" = "1" ]
  _ext_reload
  [ "$RELOADED" = "2" ]
}
