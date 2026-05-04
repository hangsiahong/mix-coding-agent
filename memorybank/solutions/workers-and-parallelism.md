# Workers & Parallelism

## Architecture

Mix uses **tmux windows** as parallel execution slots. Two types: dumb bash workers and full mix subagents.

## Dumb Bash Workers
- `/worker <name> <cmd>` → `tmux new-window -n <name>`
- Fire-and-forget bash processes. No LLM, no tools, no reasoning.
- Main agent polls via `tmux capture-pane -p -t <name>` or `tail -f /tmp/<name>.log`.

## Subagents (Full Mix Instances)
- `/subagent <name> <task>` → spawns new mix instance in tmux window
- Task piped via stdin. Full tool use, streaming, git integration.
- Logs to `/tmp/<name>.log`.
- When finished, sends notification to parent tty.

## Limitations
- Single LLM context manages all workers — doesn't scale to many concurrent tasks.
- No structured inter-worker communication.
- Workers are independent — no shared state except filesystem.

## Source
- `src/25_repl_commands.sh` — /worker, /subagent, /workers
- `src/02_tmux_bootstrap.sh` — tmux session bootstrap
