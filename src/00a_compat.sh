# ─── Platform Compatibility Layer ──────────────────────────────────────────
# Provides portable wrappers for GNU-coreutils-specific commands on macOS.
# Loaded first (00a) so all other modules use these wrappers.
#
# Handles: stat, date (nanoseconds), readlink -f, sed -i, base64 -d

# Detect platform once
_MIX_OS="$(uname -s 2>/dev/null || echo Linux)"

# ─── stat: get file mtime ──────────────────────────────────────────────────
# GNU: stat -c '%Y' file   →  macOS: stat -f '%m' file
_mix_stat_mtime() {
  local _f="$1"
  if [ "$_MIX_OS" = Darwin ]; then
    stat -f '%m' "$_f" 2>/dev/null || echo 0
  else
    stat -c '%Y' "$_f" 2>/dev/null || echo 0
  fi
}

# ─── date: high-resolution epoch (milliseconds) ────────────────────────────
# GNU: date +%s%N  →  macOS: python3 fallback
# Returns epoch in nanoseconds (Linux) or milliseconds*1000000 (macOS)
# For unique-id purposes, both are fine.
_mix_date_nano() {
  if [ "$_MIX_OS" = Darwin ]; then
    python3 -c 'import time; print(int(time.time()*1e9))' 2>/dev/null || date +%s000000000
  else
    date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))'
  fi
}

# ─── readlink -f: resolve canonical path ───────────────────────────────────
# macOS has no readlink -f. Use python3 or manual resolution.
_mix_readlink_f() {
  local _p="$1"
  if [ "$_MIX_OS" = Darwin ]; then
    # python3 is already a required dependency
    python3 -c "import os; print(os.path.realpath('$_p'))" 2>/dev/null || echo "$_p"
  else
    readlink -f "$_p" 2>/dev/null || echo "$_p"
  fi
}

# ─── sed -i: in-place edit ────────────────────────────────────────────────
# macOS sed -i requires a backup suffix (empty string for no backup)
_mix_sed_i() {
  local _expr="$1" _file="$2"
  if [ "$_MIX_OS" = Darwin ]; then
    sed -i '' "$_expr" "$_file"
  else
    sed -i "$_expr" "$_file"
  fi
}

# ─── base64 decode ─────────────────────────────────────────────────────────
# macOS: base64 -D (old), base64 -d (modern macOS 11+)
# Both -d and -D work on modern macOS, but use -d with python3 fallback
_mix_base64_decode() {
  if [ "$_MIX_OS" = Darwin ]; then
    base64 -D 2>/dev/null || python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))'
  else
    base64 -d 2>/dev/null || python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))'
  fi
}

# ─── timeout: run command with time limit ──────────────────────────────────
# GNU coreutils `timeout` not available on macOS by default.
# Fallback to perl (universally available on macOS) or background+kill.
_mix_timeout() {
  local _dur="$1"; shift
  if [ "$_MIX_OS" = Darwin ]; then
    # perl is guaranteed on macOS
    perl -e 'alarm shift @ARGV; exec @ARGV' "$_dur" "$@" 2>/dev/null
  else
    timeout "$_dur" "$@"
  fi
}

# ─── realpath: resolve path ──────────────────────────────────────────────
# macOS doesn't have realpath. python3 fallback.
_mix_realpath() {
  python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null || echo "$1"
}
