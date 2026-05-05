#!/usr/bin/env bash
exec > /tmp/repomap-debug.log 2>&1
set -x
echo "=== START ==="
./mix --repomap
echo "=== EXIT=$? ==="