# mix

Super minimal terminal coding agent. Single bash script, zero dependencies beyond `bash curl python3`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/hangsiahong/mix-coding-agent/master/install.sh | bash
```

That's it. The installer:
- checks for `bash` `curl` `python3`
- downloads `mix` to `~/bin/` (no sudo needed)
- asks for your API key and saves it to your shell profile
- prints `mix is ready`

Then run it from any directory:

```bash
mix
```

> **API key** — mix uses [KConsole AI Gateway](https://ai.koompi.cloud) (free). Get a key at [ai.koompi.cloud](https://ai.koompi.cloud), then set:
> ```bash
> export KCONSOLE_API_KEY=your_key
> ```

---

## What it does

- Talks to any OpenAI-compatible API
- Runs tools: `bash` `read_file` `edit_file` `list_files`
- Streams tokens live as they arrive
- Maintains a `memorybank/` — compounding knowledge base across sessions
- git-safe: diffs every edit before applying, auto-commits, rollback on decline
- Risk-aware: BLOCKED / HIGH / MED / LOW gates on every shell command
- Self-healing: retries with `sudo` on permission denied, `npx` on command not found
- Auto-compacts history when context fills up

## Config

```bash
export KCONSOLE_API_KEY=your_key   # required
export AGENT_MODEL=glm-5           # default model
export AGENT_MODE=fast             # fast | deep | plan
export CAVEMAN_MODE=full           # off | lite | full | ultra
export CTX_TOKENS=131072           # context window size (for % bar)
export MAX_HIST_MSGS=60            # auto-compact threshold
```

## REPL commands

| command | action |
|---|---|
| `/flush` | clear conversation history |
| `/compact` | force-compact history now |
| `/model [id]` | swap model mid-session |
| `/mode [fast\|deep\|plan]` | change reasoning mode |
| `/caveman [off\|lite\|full\|ultra]` | response compression level |
| `/yolo` | toggle auto-confirm (on by default) |
| `/exit` | quit |

## Project extensions

Drop a `.agent/rc.sh` in any project directory — mix sources it at startup:

```bash
# .agent/rc.sh
TEST_CMD="npm test"
MODEL="gpt-4o"
```

Global overrides: `~/.mix/rc.sh`

## Memory bank

`memorybank/` is an LLM-maintained knowledge base. Create it and mix will:
- append task log entries to `memorybank/log.md`
- auto-file solved problems to `memorybank/solutions/`
- maintain an index at `memorybank/index.md`

```
memorybank/
  index.md        content catalog
  log.md          append-only task timeline
  solutions/      per-problem markdown pages
  sources/        ingested source summaries
```

## Risk model

| level | behaviour |
|---|---|
| BLOCKED | hard stop — fork bombs, disk wipes, rm -rf system paths |
| HIGH | must type `YES` even in yolo — remote exec, force push, sudo destruct |
| MED | `[Y/n]` prompt — pkg install, git writes, file delete/move |
| LOW | auto-run silently |

## Tmux

When running inside tmux, mix auto-renames the window to `mix` and updates `status-right` with model, git branch, and context %:

```
mix glm-5 | master | ctx 12%
```

---

single file. no install. just run it.

