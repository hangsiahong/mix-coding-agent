# Sandbox Mode — Alpine Chroot + Linux Namespaces + Cgroup v2

## Problem

mix executes bash commands from LLM output. Without isolation, a bad tool call can damage the host system, leak credentials from other projects, or install malicious packages globally.

## Why not execc / Docker / podman?

| Option | Problem |
|---|---|
| [execc](https://github.com/nicholaswilde/execc) | cgroup v1 only, uses `eval`, 486 lines of fragile bash, would need forking |
| Docker / podman | Breaks zero-install philosophy. Large daemon. Not available on all systems. |
| bubblewrap (`bwrap`) | Extra binary dependency. Not universally installed. |
| **Linux namespaces (chosen)** | Built into kernel ≥3.8. `unshare` is part of `util-linux` (present everywhere). Zero new deps. |

## Design

**Full Alpine chroot mode only** — no "lite" mode with incomplete isolation.

Rootfs lifecycle:
1. `/sandbox setup` — downloads `sandbox-rootfs.tar.gz` from GitHub Releases, extracts to `~/.mix/sandbox-rootfs/`
2. `/sandbox on` — sets `SANDBOX_ENABLED=true`, all subsequent `bash` tool calls routed through `sandbox_run_cmd()`  
3. `/sandbox off` — restores direct execution
4. `apk add` inside sandbox persists to `~/.mix/sandbox-rootfs/` (writable bind mounts)

## Critical Implementation Detail: Bind Mounts Inside Namespace

**Problem**: When doing `unshare --user --map-root-user`, the calling process becomes uid=0 *inside* the namespace — but is still a regular user *outside*. Attempting bind mounts as the real user before entering the namespace fails with `EPERM`.

**Solution**: All bind mounts happen INSIDE the unshare heredoc where fake-root privileges apply.

```bash
unshare --fork --pid --mount --user --map-root-user bash <<'INNER'
  # Now uid=0 inside namespace — bind mounts work
  mount --bind /path/to/project "$rootfs/workspace"
  mount --bind "$HOME/.mix" "$rootfs/root/.mix"
  mount --bind /etc/resolv.conf "$rootfs/etc/resolv.conf"
  exec chroot "$rootfs" /bin/bash -c "$cmd"
INNER
```

## Cgroup v2 Resource Limits

No `cgroup-tools` needed. Write directly to `/sys/fs/cgroup`:

```bash
# Find user's own cgroup slice (writable without root)
local base=$(cat /proc/self/cgroup | grep '^0:' | cut -d: -f3)
local cg="/sys/fs/cgroup${base}/mix-sandbox-$$"

mkdir -p "$cg"
echo "536870912" > "$cg/memory.max"    # 512MB
echo "500000 1000000" > "$cg/cpu.max"  # 50% CPU
echo "200" > "$cg/pids.max"
echo $$ > "$cg/cgroup.procs"
```

Limits:
- Memory: 512MB (`memory.max`)
- CPU: 50% of one core (`cpu.max = 500000 1000000`)
- PIDs: 200 (`pids.max`)

## Namespace Flags

```
unshare --fork --pid --mount --user --map-root-user
```

| Flag | Effect |
|---|---|
| `--fork` | Fork before exec (required for PID namespace) |
| `--pid` | New PID namespace — processes inside can't see host PIDs |
| `--mount` | New mount namespace — mounts inside don't affect host |
| `--user` | New user namespace |
| `--map-root-user` | Map calling UID to uid=0 inside namespace |

## System Prompt Injection

When `SANDBOX_ENABLED=true`, a context block is injected into the system prompt:

```
SANDBOX ACTIVE: You are running inside an Alpine Linux 3.21.x chroot.
- /workspace = project directory (same files as outside)
- /root/.mix = your ~/.mix from the host
- Use `apk add <pkg>` to install tools (nodejs, rust, shellcheck, etc.)
- apk installs persist between tool calls (rootfs is writable)
- Network: HTTPS works. Host localhost is NOT reachable.
- Resource limits: 512MB RAM, 50% CPU, 200 PIDs
- uid=0 (root) inside sandbox — normal, not a security escalation
```

## File Layout

```
~/.mix/
├── sandbox-rootfs.tar.gz    # 26MB compressed download
└── sandbox-rootfs/          # 65MB extracted Alpine rootfs
    ├── bin/, sbin/, usr/    # Alpine base + bash + python3 + curl + git
    ├── workspace -> (bind)  # project directory
    ├── root/.mix -> (bind)  # host ~/.mix
    └── etc/resolv.conf      # (bind) for DNS
```

## Source Files

| File | Role |
|---|---|
| `src/30_sandbox.sh` | Full implementation: setup, on/off, run, cgroup, prereqs |
| `src/13_tool_execution.sh` | Routes `bash` tool calls through `sandbox_run_cmd()` |
| `src/25_repl_commands.sh` | `/sandbox` REPL commands |
| `src/27_main_repl.sh` | `--sandbox` CLI flag, tab-complete |
| `src/01_config.sh` | `SANDBOX_ENABLED` default |
| `src/26_banner.sh` | 🔒 banner indicator |
| `src/03_system_prompt_*.sh` | Alpine context injection |

## Usage

```bash
# One-time setup
mix
/sandbox setup

# Enable for a session
/sandbox on

# Or start with sandbox active
mix --sandbox

# Check status
/sandbox status

# Install a tool inside sandbox (persists)
> run: apk add shellcheck

# Disable
/sandbox off
```

## Verified Behavior

- `id` → `uid=0(root) gid=0(root)` inside sandbox
- `cat /etc/alpine-release` → `3.21.3`
- `/home/jiren` not accessible inside (bind-mounted items only)
- `curl https://...` works (network available)
- `/sys/fs/cgroup/.../pids.current` shows tracked PIDs
- `apk add nodejs` works and persists across calls
