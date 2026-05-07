#!/usr/bin/env bash
# Test helper — source individual modules under test
# Avoids loading the full mix binary (which starts REPL, tmux, etc.)

BATS_TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
PROJECT_ROOT="$(cd "$BATS_TEST_DIR/.." && pwd)"

# Export vars that modules reference
WORKDIR="$PROJECT_ROOT"
AUTO_VERIFY="off"

# Source individual source files (order matters — earlier deps first)
source "$PROJECT_ROOT/src/00a_compat.sh"
source "$PROJECT_ROOT/src/00_header.sh"
source "$PROJECT_ROOT/src/00b_icons.sh"

# Helper: source a specific module
_load_module() {
  source "$PROJECT_ROOT/src/$1"
}
