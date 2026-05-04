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
SANDBOX ACTIVE: bash tool runs inside Alpine Linux 3.21.x chroot with full namespace isolation.
- /workspace = project directory (bind-mounted from host)
- /root/.mix = ~/.mix from host
- Network: FULLY ISOLATED inside bash tool. No internet, no LAN. Loopback only.
  apk add cannot be run inside bash tool calls — network is blocked.
- If a package is missing: STOP and tell the user to run /sandbox install <pkg> in the REPL.
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

## Security Audit Results (3 rounds)

### Final Status: 20/22 PASS

| # | Attack Vector | Result |
|---|---|---|
| /proc/1/root host read | Sandbox rootfs only | ✅ PASS |
| /proc/1/root host write | Blocked (sandbox /tmp) | ✅ PASS |
| SSH key read | No such file | ✅ PASS |
| chroot escape | Re-enters sandbox only | ✅ PASS |
| API key leak (/proc/1/environ) | Not found | ✅ PASS |
| Network isolation | Only loopback visible | ✅ PASS |
| Outbound internet | Blocked (HTTP 000) | ✅ PASS |
| /proc mounted nosuid,nodev,noexec | Confirmed | ✅ PASS |
| sysrq-trigger | Masked /dev/null ro | ✅ PASS |
| PID visibility | 1 PID only | ✅ PASS |
| mknod devices | EPERM | ✅ PASS |
| block devices | No access | ✅ PASS |
| su/sudo | Blocked | ✅ PASS |
| mount/pivot_root/nsenter | Blocked | ✅ PASS |
| /proc/1/mem | I/O error | ✅ PASS |
| /etc/shadow | Sandbox copy only | ✅ PASS |
| CapEff = 0xfff... | User ns scoped — non-exploitable | ⚠️ LOW |
| mountinfo host paths | Info disclosure — no access | ⚠️ LOW |

### What Each Fix Round Closed

**Round 1 — `exec chroot` (critical fix)**
- Root cause: `chroot cmd` creates a child process; PID 1 (the outer `sh -s`) stays un-chrooted with host root. `/proc/1/root` = full host filesystem read+write.
- Fix: `exec chroot` **replaces** PID 1 with the chrooted process. After exec, `/proc/1/root` = sandbox rootfs.
- Also clears API keys (`unset KCONSOLE_API_KEY ...`) before exec to prevent `/proc/1/environ` leak.

**Round 2 — network namespace + proc hardening**
- Added `--net` to `unshare` flags: isolated network namespace, only `lo` visible.
- `apk add` won't work inside sandbox bash tool calls (no network). Use `/sandbox install <pkg>` from the REPL instead — it runs apk add with network and persists to the rootfs.
- Loopback brought up (`ip link set lo up`) for local dev servers.
- `/proc` mounted with `nosuid,nodev,noexec` options.
- `sysrq-trigger` masked with read-only `/dev/null` bind.

**Round 3 — file tool path guards**
- `read_file`, `edit_file`, `create_file`, `list_files`, `search_files` restricted to `$WORKDIR` and `~/.mix` when `SANDBOX_ENABLED=true`.
- Closes host filesystem escape via file tools (previously could read `/home/jiren/.ssh/id_rsa`, `~/.bashrc`, `/etc/passwd`).

**Round 4 — rootfs read-only mounts**
- Reverse shell penetration test confirmed: bash/python sockets, curl, DNS all blocked by `--net`.
- `/tmp` confirmed isolated (not bind-mounted from host; ephemeral in sandbox-rootfs).
- rootfs system dirs (`/bin`, `/etc`, `/lib`, `/sbin`, `/usr`, `/var`) now mounted **read-only** inside `sandbox_run_cmd`.
- Prevents LLM from poisoning rootfs for cross-session persistence.
- `/sandbox install` still writes to rootfs (direct chroot on host, outside the namespace).

### Remaining Low-Risk Items (non-exploitable)

1. **Capabilities (`CapEff: 0x1ffffffffff`)** — expected in user namespaces. These capabilities only apply within the namespace and map to unprivileged uid 1000 on the host. Cannot cross namespace boundary.
2. **mountinfo leaks host device paths** (`/dev/nvme0n1p9`, `@home/jiren/...`) — information disclosure only. No actual file access possible through it.

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

# Install a tool into the sandbox rootfs (runs apk add with network, from REPL)
/sandbox install shellcheck

# Disable
/sandbox off
```

### Round 4 — Reverse Shell Penetration Test

**Scenario**: Malicious prompt tricks LLM into writing and executing reverse TCP shells.

| # | Attack | Result |
|---|---|---|
| Bash reverse shell (`/dev/tcp/10.0.0.1/4444`) | `Network unreachable` | ✅ BLOCKED |
| Python socket reverse shell | `Errno 101: Network unreachable` | ✅ BLOCKED |
| curl exfiltration | `Network unreachable` | ✅ BLOCKED |
| DNS resolution (google.com) | `Errno -3: Try again` | ✅ BLOCKED |
| Named pipe (FIFO backchannel) | Ephemeral in sandbox /tmp only | ✅ BLOCKED |
| Cron dropper persistence | Cannot influence host cron | ✅ BLOCKED |

**Key discovery: `/tmp` IS isolated** (correcting Round 3 finding):
- `/tmp` is NOT bind-mounted from host — it's an empty dir inside `sandbox-rootfs/`
- `mountinfo` confirms no `/tmp` bind mount entry
- Files written to `/tmp` are ephemeral, destroyed when sandbox exits

**Actual write surface to host** (by design, unavoidable):

| Path | Mount | Risk |
|---|---|---|
| `/workspace` | `$WORKDIR` (rw) | LLM can drop trojan files |
| `/root/.mix` | `~/.mix` (rw) | LLM can plant scripts in agent config |
| `/bin,/etc,/lib,/usr,/var,/sbin` | `sandbox-rootfs/` (rw) | LLM can poison rootfs for persistence |

**Attack chain analysis**:
```
Step 1: LLM writes evil.sh to /workspace        → POSSIBLE (by design)
Step 2: evil.sh calls home from inside sandbox   → IMPOSSIBLE (no network)
Step 3: User runs evil.sh on host                → POSSIBLE (social engineering)
Step 4: Reverse shell connects out from host     → POSSIBLE (host has network)
```

**Verdict**: Sandbox prevents DIRECT compromise. The remaining risk is social engineering — user must explicitly run a dropped file on the host. This is the same trust model as any development tool (vim, VS Code, etc.).

**Recommended hardening** (IMPLEMENTED Round 5):
1. ✅ Mount rootfs dirs (`/bin,/etc,/lib,/sbin,/usr,/var`) as **read-only** by default; remount rw only during `/sandbox install`
2. Restrict `~/.mix` writes to allowlist (session.json, history, extensions only) — not yet implemented

## Verified Behavior

- `id` → `uid=0(root) gid=0(root)` inside sandbox
- `cat /etc/alpine-release` → `3.21.3`
- `/home/jiren` not accessible inside (bind-mounted items only)
- `curl https://...` BLOCKED inside bash tool (network isolated, `--net` namespace)
- Loopback works: `curl http://localhost:3000` inside bash tool is fine
- `/sys/fs/cgroup/.../pids.current` shows tracked PIDs
- `/sandbox install nodejs` from REPL installs via apk add (network available) and persists
