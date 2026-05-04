# ─── Sandbox ─────────────────────────────────────────────────────────────────
# Full container-level isolation via Linux namespaces + cgroup v2.
# No Docker, no podman. Pure unshare + chroot + direct /sys/fs/cgroup writes.
#
# Usage:
#   /sandbox setup    — download Alpine rootfs + install deps (~35MB, one-time)
#   /sandbox on       — enable sandbox for this session (requires setup first)
#   /sandbox off      — disable sandbox
#   /sandbox status   — show current state
#   /sandbox build    — build rootfs from scratch instead of downloading
#
# State variable: SANDBOX_ENABLED (true/false)
# Rootfs location: ~/.mix/sandbox-rootfs.tar.gz (packed) / ~/.mix/sandbox-rootfs/ (unpacked)

SANDBOX_ENABLED="${SANDBOX_ENABLED:-false}"
_SANDBOX_ROOTFS_TAR="${HOME}/.mix/sandbox-rootfs.tar.gz"
_SANDBOX_ROOTFS_DIR="${HOME}/.mix/sandbox-rootfs"
_SANDBOX_ROOTFS_VERSION="${HOME}/.mix/sandbox-rootfs.version"
_SANDBOX_ARCH="$(uname -m)"
# Map uname -m to Alpine arch names
case "$_SANDBOX_ARCH" in
  x86_64)  _SANDBOX_ALPINE_ARCH="x86_64" ;;
  aarch64) _SANDBOX_ALPINE_ARCH="aarch64" ;;
  armv7l)  _SANDBOX_ALPINE_ARCH="armv7" ;;
  *)       _SANDBOX_ALPINE_ARCH="$_SANDBOX_ARCH" ;;
esac

_SANDBOX_ALPINE_VERSION="3.21.3"
_SANDBOX_ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/${_SANDBOX_ALPINE_ARCH}/alpine-minirootfs-${_SANDBOX_ALPINE_VERSION}-${_SANDBOX_ALPINE_ARCH}.tar.gz"

# ── Prereq check ─────────────────────────────────────────────────────────────
sandbox_check_prereqs() {
  local ok=true
  for cmd in unshare chroot curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo -e "  \033[1;31m✗\033[0m Missing required command: $cmd"
      ok=false
    fi
  done
  # Check user namespace support
  if ! unshare --user --map-root-user true 2>/dev/null; then
    echo -e "  \033[1;31m✗\033[0m Unprivileged user namespaces not available."
    echo "    On Debian/Ubuntu: sysctl -w kernel.unprivileged_userns_clone=1"
    ok=false
  fi
  [ "$ok" = true ]
}

# ── Find writable cgroup v2 path under user's own slice ──────────────────────
_sandbox_cgroup_base() {
  # Walk /proc/self/cgroup to find our user session cgroup
  local selfcg; selfcg=$(cat /proc/self/cgroup 2>/dev/null | cut -d: -f3 | head -1)
  # selfcg looks like /user.slice/user-1000.slice/user@1000.service/app.slice/...
  # Walk up until we find a directory we own
  local base="/sys/fs/cgroup${selfcg}"
  while [ "$base" != "/sys/fs/cgroup" ]; do
    if [ -w "$base/cgroup.procs" ]; then
      printf '%s' "$base"
      return 0
    fi
    base="$(dirname "$base")"
  done
  # Fallback: user@UID.service path
  local uid; uid=$(id -u)
  local candidate="/sys/fs/cgroup/user.slice/user-${uid}.slice/user@${uid}.service"
  if [ -w "${candidate}/cgroup.procs" ]; then
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

# ── Create a fresh per-run cgroup for resource limits ────────────────────────
# Sets memory.max and cpu.max, writes PID in, returns cgroup path via stdout
_sandbox_cgroup_create() {
  # Default memory: 50% of total RAM, minimum 512MB
  local _total_kb; _total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null) || _total_kb=1048576
  local _default_mem=$(( _total_kb * 512 ))   # 50% of RAM in bytes (total_kb/2 * 1024)
  [ "$_default_mem" -lt 536870912 ] && _default_mem=536870912  # floor: 512MB
  local mem_bytes="${1:-$_default_mem}"
  local cpu_quota="${2:-500000}"      # default 50% of 1 core (500ms per 1s period)
  local cpu_period="1000000"

  local base; base=$(_sandbox_cgroup_base 2>/dev/null) || { echo "" ; return 1; }
  local cgpath="${base}/mix-sandbox-$$"

  mkdir "$cgpath" 2>/dev/null || { echo ""; return 1; }

  # Set limits — ignore failures (older kernels may not have all controllers)
  echo "$mem_bytes" > "${cgpath}/memory.max" 2>/dev/null || true
  echo "$cpu_quota $cpu_period" > "${cgpath}/cpu.max" 2>/dev/null || true
  # Prevent fork bombs
  echo "200" > "${cgpath}/pids.max" 2>/dev/null || true

  printf '%s' "$cgpath"
}

_sandbox_cgroup_cleanup() {
  local cgpath="$1"
  [ -z "$cgpath" ] && return
  [ -d "$cgpath" ] || return
  # Move any remaining procs to parent before rmdir
  local parent; parent="$(dirname "$cgpath")"
  if [ -w "${parent}/cgroup.procs" ]; then
    while IFS= read -r pid; do
      echo "$pid" > "${parent}/cgroup.procs" 2>/dev/null || true
    done < "${cgpath}/cgroup.procs" 2>/dev/null || true
  fi
  rmdir "$cgpath" 2>/dev/null || true
}

# ── Unpack rootfs (only if not already unpacked or stale) ────────────────────
_sandbox_unpack_rootfs() {
  local tarversion="" dirversion=""
  [ -f "$_SANDBOX_ROOTFS_VERSION" ] && dirversion=$(cat "$_SANDBOX_ROOTFS_VERSION")

  if [ -d "$_SANDBOX_ROOTFS_DIR" ] && [ "$dirversion" = "$_SANDBOX_ALPINE_VERSION" ]; then
    return 0  # Already unpacked at correct version
  fi

  if [ ! -f "$_SANDBOX_ROOTFS_TAR" ]; then
    echo -e "  \033[1;31m✗\033[0m Rootfs not found. Run: /sandbox setup"
    return 1
  fi

  echo -e "  \033[0;90m↻ Unpacking rootfs...\033[0m"
  rm -rf "$_SANDBOX_ROOTFS_DIR"
  mkdir -p "$_SANDBOX_ROOTFS_DIR"
  tar -C "$_SANDBOX_ROOTFS_DIR" -xzf "$_SANDBOX_ROOTFS_TAR" 2>/dev/null || {
    rm -rf "$_SANDBOX_ROOTFS_DIR"
    echo -e "  \033[1;31m✗\033[0m Failed to unpack rootfs tar."
    return 1
  }
  echo "$_SANDBOX_ALPINE_VERSION" > "$_SANDBOX_ROOTFS_VERSION"
}

# ── Run a command inside the sandbox ─────────────────────────────────────────
# Usage: sandbox_run_cmd "bash command string"
# Returns output of the command. Used by run_tool() to wrap bash calls.
#
# Design: all bind mounts happen INSIDE the unshare call, where --map-root-user
# gives us fake root in the mount namespace — no real root required.
sandbox_run_cmd() {
  local cmd="$1"
  local rfs="$_SANDBOX_ROOTFS_DIR"

  if [ ! -d "$rfs" ]; then
    echo "[SANDBOX ERROR] Rootfs not found at $rfs. Run /sandbox setup."
    return 1
  fi

  # Scratch dir for the chroot tree — cleaned up after unshare exits
  local mntdir; mntdir=$(mktemp -d /tmp/mix-sbox-XXXXXX)
  local cgpath=""

  _sbox_cleanup() {
    rm -rf "$mntdir" 2>/dev/null || true
    _sandbox_cgroup_cleanup "$cgpath"
  }
  trap _sbox_cleanup EXIT

  # Pre-create dirs the inner script will mount into
  mkdir -p "${mntdir}"/{proc,tmp,workspace,root/.mix}
  for d in bin etc lib lib64 sbin usr var; do
    [ -d "${rfs}/$d" ] && mkdir -p "${mntdir}/$d"
  done

  # Cgroup: created outside namespace (no privilege needed for user slice writes)
  cgpath=$(_sandbox_cgroup_create 2>/dev/null) || cgpath=""
  [ -n "$cgpath" ] && echo $$ > "${cgpath}/cgroup.procs" 2>/dev/null || true

  local workspace="$WORKDIR"
  local mix_home="${HOME}/.mix"
  local host_resolv="/etc/resolv.conf"

  # ── All bind mounts run inside the user+mount namespace ───────────────────
  # Inside unshare --user --map-root-user we appear as root, so mount --bind
  # works without any real privilege escalation.
  local out rc
  out=$(
    unshare \
      --fork \
      --pid \
      --mount-proc="${mntdir}/proc" \
      --mount \
      --user \
      --map-root-user \
      -- \
      /bin/sh -s "$mntdir" "$rfs" "$workspace" "$mix_home" "$host_resolv" "$cmd" << 'INNER'
mntdir="$1" rfs="$2" workspace="$3" mix_home="$4" host_resolv="$5"
shift 5; cmd="$*"

# Bind Alpine rootfs dirs (writable) — LLM can run "apk add rust typescript" etc.
# Changes persist to ~/.mix/sandbox-rootfs/ between sessions, like a managed dev container.
for d in bin etc lib lib64 sbin usr var; do
  [ -d "${rfs}/$d" ] || continue
  mkdir -p "${mntdir}/$d"
  mount --bind "${rfs}/$d" "${mntdir}/$d" 2>/dev/null || true
done

# Override resolv.conf with host DNS so API calls work
# Alpine rootfs ships /etc/resolv.conf already — bind host file on top
mount --bind -o ro "$host_resolv" "${mntdir}/etc/resolv.conf" 2>/dev/null || \
  true  # non-fatal: Alpine's empty resolv.conf still allows loopback

# Workspace: writable bind mount at /workspace
mount --bind "$workspace" "${mntdir}/workspace" 2>/dev/null || {
  echo "[SANDBOX ERROR] Cannot bind-mount workspace ($workspace). Check kernel mount namespace support."
  exit 1
}

# Mix config: writable so session/history persist
[ -d "$mix_home" ] && mount --bind "$mix_home" "${mntdir}/root/.mix" 2>/dev/null || true

# Execute inside the chroot
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
chroot "$mntdir" /bin/sh -c "cd /workspace && $cmd"
INNER
  ) 2>&1; rc=$?

  trap - EXIT
  _sbox_cleanup

  [ $rc -ne 0 ] && [[ "$out" != "[FAILED"* ]] && out="[FAILED exit=$rc]
$out"
  printf '%s' "$out"
}

# ── /sandbox setup — download Alpine + install deps ──────────────────────────
sandbox_cmd_setup() {
  echo -e "\n  \033[1;37m── Sandbox Setup ──\033[0m"

  if ! sandbox_check_prereqs; then
    echo -e "  \033[1;31m✗ Prerequisite check failed.\033[0m"
    return 1
  fi

  # Check if already set up
  if [ -f "$_SANDBOX_ROOTFS_TAR" ]; then
    local _ver=""
    [ -f "$_SANDBOX_ROOTFS_VERSION" ] && _ver=$(cat "$_SANDBOX_ROOTFS_VERSION")
    if [ "$_ver" = "$_SANDBOX_ALPINE_VERSION" ]; then
      echo -e "  \033[38;5;82m✓\033[0m Rootfs already built (Alpine $_SANDBOX_ALPINE_VERSION, arch: $_SANDBOX_ALPINE_ARCH)"
      echo "  Run /sandbox on to activate, or /sandbox setup --rebuild to rebuild."
      return 0
    fi
  fi

  mkdir -p "${HOME}/.mix"

  echo -e "  \033[0;90mArch: $_SANDBOX_ARCH → Alpine $_SANDBOX_ALPINE_ARCH\033[0m"
  echo -e "  \033[0;90mAlpine version: $_SANDBOX_ALPINE_VERSION\033[0m"
  echo ""

  # ── Step 1: Download Alpine mini rootfs ─────────────────────────────────
  local _base_tar; _base_tar=$(mktemp /tmp/mix-alpine-base-XXXXXX.tar.gz)
  echo -e "  \033[1;36m[1/3]\033[0m Downloading Alpine base rootfs..."
  echo -e "  \033[0;90m$_SANDBOX_ALPINE_URL\033[0m"

  if ! curl -L --progress-bar \
      --connect-timeout 30 \
      --max-time 300 \
      "$_SANDBOX_ALPINE_URL" \
      -o "$_base_tar" 2>&1; then
    echo -e "  \033[1;31m✗ Download failed.\033[0m"
    rm -f "$_base_tar"
    return 1
  fi

  # Verify it's a valid tar
  if ! tar -tzf "$_base_tar" >/dev/null 2>&1; then
    echo -e "  \033[1;31m✗ Downloaded file is not a valid tar.gz (download may have failed).\033[0m"
    rm -f "$_base_tar"
    return 1
  fi

  # ── Step 2: Bootstrap apk inside user namespace ──────────────────────────
  echo -e "  \033[1;36m[2/3]\033[0m Building rootfs (installing bash, python3, curl, git)..."
  local _build_dir; _build_dir=$(mktemp -d /tmp/mix-rootfs-build-XXXXXX)

  tar -C "$_build_dir" -xzf "$_base_tar" 2>/dev/null
  rm -f "$_base_tar"

  # Copy host DNS so apk can reach the internet
  cp /etc/resolv.conf "${_build_dir}/etc/resolv.conf" 2>/dev/null || true

  # Run apk inside a user namespace so it thinks it's root
  local _apk_out; _apk_out=$(
    unshare --user --map-root-user --fork --mount \
      chroot "$_build_dir" \
      /bin/sh -c \
      'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && apk update --no-progress 2>&1 && apk add --no-cache --no-progress bash python3 curl git 2>&1' \
    2>&1
  )
  local _apk_rc=$?

  if [ $_apk_rc -ne 0 ]; then
    echo -e "  \033[1;31m✗ apk install failed:\033[0m"
    echo "$_apk_out" | sed 's/^/    /'
    rm -rf "$_build_dir"
    return 1
  fi

  # Show installed sizes
  local _sz; _sz=$(du -sh "$_build_dir" 2>/dev/null | cut -f1)
  echo -e "  \033[0;90m  Rootfs size: $_sz\033[0m"

  # ── Step 3: Pack to tar.gz ───────────────────────────────────────────────
  echo -e "  \033[1;36m[3/3]\033[0m Packing rootfs..."
  local _final_tar; _final_tar=$(mktemp /tmp/mix-rootfs-final-XXXXXX.tar.gz)

  tar -C "$_build_dir" -czf "$_final_tar" . 2>/dev/null
  rm -rf "$_build_dir"

  mv "$_final_tar" "$_SANDBOX_ROOTFS_TAR"
  echo "$_SANDBOX_ALPINE_VERSION" > "$_SANDBOX_ROOTFS_VERSION"

  local _final_sz; _final_sz=$(du -sh "$_SANDBOX_ROOTFS_TAR" 2>/dev/null | cut -f1)
  echo ""
  echo -e "  \033[38;5;82m✓ Sandbox rootfs ready!\033[0m"
  echo "  Location: $_SANDBOX_ROOTFS_TAR ($_final_sz)"
  echo ""
  echo -e "  Run \033[1;37m/sandbox on\033[0m to enable sandbox mode."
}

# ── /sandbox status ───────────────────────────────────────────────────────────
sandbox_cmd_status() {
  local _marker="${WORKDIR:-$PWD}/.mix/sandbox"
  echo -e "\n  \033[1;37m── Sandbox Status ──\033[0m"
  echo "  State:     $([ "$SANDBOX_ENABLED" = "true" ] && echo -e "\033[38;5;82menabled\033[0m" || echo -e "\033[0;90mdisabled\033[0m")"
  if [ -f "$_marker" ]; then
    echo -e "  Project:   \033[38;5;82m✓\033[0m auto-enabled for this workspace (.mix/sandbox)"
  else
    echo -e "  Project:   \033[0;90m○\033[0m not pinned (run /sandbox on to persist)"
  fi
  echo "  Arch:      $_SANDBOX_ARCH"

  if [ -f "$_SANDBOX_ROOTFS_TAR" ]; then
    local _ver=""; [ -f "$_SANDBOX_ROOTFS_VERSION" ] && _ver=$(cat "$_SANDBOX_ROOTFS_VERSION")
    local _sz; _sz=$(du -sh "$_SANDBOX_ROOTFS_TAR" 2>/dev/null | cut -f1)
    echo -e "  Rootfs:    \033[38;5;82m✓\033[0m present (Alpine $_ver, $_sz compressed)"
  else
    echo -e "  Rootfs:    \033[1;31m✗\033[0m not found — run /sandbox setup"
  fi

  # Check cgroup availability
  local _cgbase; _cgbase=$(_sandbox_cgroup_base 2>/dev/null) || _cgbase=""
  if [ -n "$_cgbase" ]; then
    echo -e "  Cgroups:   \033[38;5;82m✓\033[0m cgroup v2 (resource limits active)"
  else
    echo -e "  Cgroups:   \033[1;33m⚠\033[0m cgroup v2 not delegated (namespace isolation only)"
  fi

  # Check user namespace
  if unshare --user --map-root-user true 2>/dev/null; then
    echo -e "  Namespaces:\033[38;5;82m ✓\033[0m user namespaces available (rootless)"
  else
    echo -e "  Namespaces:\033[1;31m ✗\033[0m user namespaces not available"
  fi
  echo ""
}

# ── /sandbox on ───────────────────────────────────────────────────────────────
sandbox_cmd_on() {
  local _marker="${WORKDIR:-$PWD}/.mix/sandbox"
  if ! sandbox_check_prereqs 2>/dev/null; then
    echo -e "  \033[1;31m✗\033[0m Sandbox prerequisites not met. See errors above."
    return 1
  fi

  if [ ! -f "$_SANDBOX_ROOTFS_TAR" ]; then
    echo -e "  \033[1;31m✗\033[0m Rootfs not found."
    echo "  Run \033[1;37m/sandbox setup\033[0m first (~35MB download, one-time)."
    return 1
  fi

  # Unpack if needed
  if ! _sandbox_unpack_rootfs; then
    return 1
  fi

  SANDBOX_ENABLED=true
  # Write marker file so sandbox auto-enables next time mix starts in this project
  mkdir -p "$(dirname "$_marker")" 2>/dev/null || true
  echo "$_SANDBOX_ALPINE_VERSION" > "$_marker" 2>/dev/null || true
  echo -e "  \033[38;5;82m✓\033[0m Sandbox \033[1;32menabled\033[0m — all bash commands run inside chroot + PID + user namespaces"
  local _cgbase; _cgbase=$(_sandbox_cgroup_base 2>/dev/null) || _cgbase=""
  if [ -n "$_cgbase" ]; then
    local _total_kb; _total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null) || _total_kb=1048576
    local _limit_mb=$(( _total_kb / 2 / 1024 ))
    [ "$_limit_mb" -lt 512 ] && _limit_mb=512
    echo "  Resource limits: ${_limit_mb}MB RAM (50% of host), 50% CPU, 200 processes"
  fi
  echo -e "  \033[0;90mPersisted to .mix/sandbox — will auto-enable next session. Use /sandbox off to disable.\033[0m"
}

# ── /sandbox off ──────────────────────────────────────────────────────────────
sandbox_cmd_off() {
  local _marker="${WORKDIR:-$PWD}/.mix/sandbox"
  SANDBOX_ENABLED=false
  rm -f "$_marker" 2>/dev/null || true
  echo -e "  \033[0;90m○\033[0m Sandbox disabled and unpinned from this workspace."
}
