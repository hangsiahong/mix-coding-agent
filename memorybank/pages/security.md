# Security Posture (2025-05)

Status: **Hardened**. Critical issues from original audit all resolved.

## What's Fixed

| ID | Issue | Fix |
|---|---|---|
| S1 | `eval "$cmd"` → arbitrary code exec | All commands use `bash -c "$cmd"` (13, 08) |
| S2 | API key in cleartext history | `save_history()` sed-redacts KCONSOLE_API_KEY (11) |
| S3 | Blind sudo retry | 08 shows full command + explicit `[y/N]` confirmation before sudo |
| S4 | Project `.agent/rc.sh` auto-sourced | 04 only sources `~/.mix/rc.sh`. Project rc removed entirely |

## Risk Scoring System (14)

Four-tier: BLOCKED → HIGH → MED → LOW

**BLOCKED** (no override):
- Fork bombs (`:(){:|:&};:`)
- Disk wipe (`dd of=/dev/sd`, `mkfs`)
- `rm -rf /` system dirs

**HIGH** (requires typed YES):
- Remote exec (`curl | bash`, `wget | python`)
- `git push --force`
- `rm -r` (recursive)
- Write to system dirs (`> /etc/...`)
- `sudo rm/dd/mkfs`

**MED** (auto-confirm in yolo mode, prompt otherwise):
- Package install (`npm install`, `pip install`, etc.)
- Git write ops (`commit`, `push`, `reset`, `rebase`, `merge`)
- Any `rm`, `mv`, `systemctl`, `service`
- File writes (`>` redirect)

**LOW**: everything else, auto-runs.

## Known Limitations

- **S5**: Fork-bomb regex only catches literal pattern. Whitespace/encoding bypass possible. Inherent regex limitation — documented, not fixable.
- **S6**: Heredoc content could theoretically hide dangerous commands from grep scan. Edge case.
- **No sandboxing**: bash -c still runs with full user permissions. Risk scoring is best-effort, not a security boundary.

## Self-Healing Wrapper (08)

`run_with_heal()` adds resilience:
1. Permission denied → show command → ask sudo confirmation
2. Command not found → check `node_modules/.bin/` → check npx (guarded: only for `pkg-name` patterns with `-` or `@`, no path separators)
3. Output truncation at 200 lines (100 head + 100 tail) to prevent context bloat
