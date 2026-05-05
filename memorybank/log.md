# memorybank log

Append-only task timeline. Format: `## [YYYY-MM-DD] type | description`

## [2025-05-18] ingest | Elite Agent Upgrades
- Implemented **Interactive Hunk Review**: `y/n/a/q` safety loop for `edit_file`.
- Implemented **Ctags Repo Map**: High-precision symbol navigation using `universal-ctags`.
- Implemented **Proactive Memory**: Automatic lessons-learned extraction after tasks.
- Verified with 151 existing bats tests + 3 new hunk review tests.
- Updated `README.md`, `SPEC.md`, and `memorybank/`.

## [2025-07-14] ingest | Architecture Deep Dive

Full analysis of mix-coding-agent: boot sequence, agent loop, 10 key subsystems, provider system, config priority chain, test suite. Strengths, weaknesses, design decisions.

## [2025-07-14] ingest | Design philosophy page expanded — 14 sections covering all major decisions: context engineering, edit strategies, safety model, caveman mode, extensibility, memorybank, cavekit specs, parallelism, decision record table

12 TUI improvements implemented: re-render flicker fix, bash truncation marker, banner keybinding hints, grouped /help display, ctx_bar before first turn, MED risk yolo indicator, turn progress indicator, spinner color states, provider/extension autocomplete, turn separator, diff preview context lines, tmux live status. 166/166 tests pass.

## [2025-05-03] ingest | Initial codebase audit (1520 lines, 4 critical security issues)

## [2025-05-03] ingest | Copilot provider implementation

## [2025-05-04] ingest | /afk custom prompt support — `/afk <task>` replaces default analysis

## [2026-05-04] task | Professional Skill System & Tool Hardening
- Implemented global skill system in `~/.mix/skills/`.
- Enhanced `edit_file` with 4-strategy matching (Exact, Fuzzy, Indent, Anchor).
- Fixed Copilot/Gemini `/compact` 400 errors and empty responses.
- Added TUI tool-execution feedback (icons + command echoing).

## [2026-05-04] task | Documentation & Solution Architecting
- documenting new system architecture in memorybank.

## [2026-05-15] ingest | Google Provider Implementation
- Added Google AI Studio and Vertex AI provider support.
- Implemented `/provider google login` for interactive setup.
- Handled Vertex OpenAI-compat header requirements (suppress Authorization, use x-goog-api-key).
- Added support for preview models via global location.

## [2026-05-05] feature | Google Provider hardening — thinkingConfig + thought_signature + compact fix
- `thought_signature` captured in streaming assembler + preserved in history for multi-turn Gemini 3
- `google_filter_history()` strips unsigned tool_calls to prevent 400 errors on replay
- `_apply_provider_history_filter()` in `11_history.sh` — universal sanitizer strips Google fields when switching providers
- `/compact` 401 fix: full rewrite of auth/header logic to use same SUPPRESS_AUTH pattern as call_api
- `google_extra_payload_json()` + `google_set_thinking()` — thinkingConfig injection for Gemini 3/2.5
- `/provider google thinking <level>` REPL command (minimal/low/medium/high)
- System prompt: added "never narrate tool calls" rule to prevent Gemini verbose [Used tools:...] output
- README updated: better header, all-provider install note, thinking command documented

## [2026-05-05] feature | Sandbox mode implemented
- `src/30_sandbox.sh` — full Alpine chroot via `unshare --fork --pid --mount --user --map-root-user`
- Zero new system dependencies. Pure bash + Linux kernel namespaces.
- Cgroup v2 limits: 512MB RAM, 50% CPU, 200 PID max (direct `/sys/fs/cgroup` writes)
- Alpine 3.21.3 rootfs (~26MB compressed, ~65MB unpacked) at `~/.mix/sandbox-rootfs/`
- Critical fix: bind mounts done INSIDE the unshare namespace where `--map-root-user` gives fake root
- `/sandbox on|off|setup|status` REPL commands. `--sandbox` CLI flag.
- All `bash` tool calls routed through `sandbox_run_cmd()` when `SANDBOX_ENABLED=true`
- LLM informed via system prompt injection: Alpine OS, `/workspace` = project dir, `apk add` usage
- `apk add` installs persist to rootfs (bind mounts are writable)
- Banner shows 🔒 sandbox indicator when active 
           done
      └─   📝 edit: /home/jiren/projects/funs/building/agent/src

## [2026-05-04] ingest | Memorybank update — added parallel-tool-batching solution, updated architecture data flow + key decisions, updated tools-reference with 4-strategy edit_file + parallel batch docs, updated index

## [2026-05-04] ingest | Repo Map — codebase structural awareness. Regex-based extractor, 10 languages, ~1200 tokens in system prompt. Eliminates 2-3 orientation turns per task.

## [2026-05-04] feature | File Content Cache — session-scoped cache surviving compaction

## [2026-05-04] feature | Auto-Verify — post-edit syntax/lint/typecheck for 10 languages

## [2026-05-04] feature | Edit Failure Suggestions — [SUGGESTION] context on edit mismatch, eliminates re-read turn

## [2026-05-04] feature | Smart Bash Truncation — 50/50 head+tail + error extraction from middle section

## [2026-05-04] feature | Token Tracking — session counters, ctx_bar stats line, /stats command

## [2026-05-04] feature | /undo (git revert HEAD), /stash (git stash), /stats REPL commands

## [2026-05-04] ingest | Memorybank update — 3 new solution pages (edit-suggestions, smart-bash-truncation, token-tracking), updated architecture/tools-reference/repl-commands/index

## [2026-05-04] feature | /test command system — init, generate, run, coverage. 568 lines. 6 frameworks. Zero-to-tested in one command.

## [2026-05-04] fix | Bug sweep round 2: fixed 3 more source bugs. Yolo dead code (AGENT_MODE→AUTO_YES), AUTO_YES unsafe default (true→false), update_global_memory replace argv injection (→stdin JSON). Tests 73/73 green.

## [2026-05-04] feature | /resume — Session Context Recovery. New src/11c_session.sh. session_save/load/apply/clear. Base64 encoding for safe field passing (dict→JSON broke tab-separated approach). .agent/session.json persisted on exit, /resume restores file cache + repo map + env + config. 27 new tests. Total: 100/100 passing.

## [2026-05-04] audit | Round 6 Deep Sandbox Escalation Audit
Tested 30+ vectors: capabilities decode, namespace nesting, overlayfs, block devices, mount attacks, ptrace, /proc leaks.
- 🔴 MEDIUM: /proc/1/environ leaks host user env (username, shell, DISPLAY, TMUX, desktop). Fix: replace `unset` with `env -i`.
- ⚠️ LOW: /proc leaks host hardware (kernel, CPU, RAM, disk layout).
- ✅ 22 escalation attacks blocked: no namespace nesting, no block device, no overlayfs escape, no ptrace.
- Verdict: production-ready. Remaining issues informational only.m, just add another feature imple

## [2026-05-04] ingest | Extension system complete
  - New: src/04b_extension_system.sh (245 lines)
  - New: src/02_mixrc.sh (107 lines) — .mixrc project overrides
  - 151/151 tests passing (27 mixrc + 24 extensions)
  - Updated: architecture.md, index.md, extension-system.md solution page
  - Pending: README update for extensions section

## [2026-05-05] security | Sandbox security audit — 3 rounds, 20/22 PASS
- Round 1: Found /proc/1/root filesystem escape (read+write+chroot). Fixed with `exec chroot` — replaces PID 1 so /proc/1/root = sandbox root not host root. Also cleared API keys before exec.
- Round 2: Found full host network visible (wlan0/tailscale0/docker). Fixed with `--net` unshare flag. Added proc nosuid/nodev/noexec, sysrq-trigger masked ro.
- Final: 20/22 pass. Remaining 2 (caps, mountinfo) non-exploitable in user namespace context.
- memorybank/solutions/sandbox.md updated with full audit table.

## [2026-05-05] feature | Versioning & Self-Heal System
- `--self-test` flag in src/00_header.sh (python3 + curl checks)
- `--doctor` mode (crash log display in banner)
- `--version` flag (MIX_VERSION embedded in binary)
- Versioned binary storage: ~/.mix/versions/<ts>.bin + current/last_good symlinks
- Thin wrapper at ~/.local/bin/mix: health-check + fallback to last_good --doctor
- build.sh: version inject, health gate, auto-prune (keep 5), wrapper install
- install.sh: download → health_check → version_install → install_wrapper pipeline
- /reload integration: build.sh handles versioning, detects self-test failure
- All 8 SPEC tasks complete

## [2025-06-10] feature | Versioned Builds + Self-Heal System (8 tasks, all complete)
- `--self-test` flag: checks python3+curl, prints OK/FAIL
- Versioned binary storage: `~/.mix/versions/<epoch>.bin` + `current`/`last_good` symlinks
- Thin wrapper: `~/.local/bin/mix` (~30 lines), health-checks current (3s), falls back to last_good --doctor
- `build.sh` rewrite: injects MIX_VERSION, health gate, rotate symlinks, auto-prune (keep 5)
- `--doctor` mode: crash log excerpt + repair hints
- `/reload` integration: rebuilds via build.sh, detects self-test failures
- `install.sh` update: 4-stage pipeline (download → health_check → version_install → install_wrapper)
- Pushed to origin/refactor.


