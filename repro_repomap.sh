#!/usr/bin/env bash
source src/00_header.sh
source src/11b_repo_map.sh

# Mock required variables if needed
export WORKDIR="."
export GIT_ENABLED=true

echo "Running build_repo_map..."
build_repo_map
echo "Done."