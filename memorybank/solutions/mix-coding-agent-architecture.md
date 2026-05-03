# Mix Coding Agent: Subagent & Parallel Working

## Summary

Mix coding agent has **worker-based parallelism via tmux**, but **no recursive sub-agents** (no LLM-in-LLM calls).

---

## Parallel Working: tmux Workers

Implemented in `src/25_repl_commands.sh` (lines 57-76).

### How it works
- Uses **tmux windows** as parallel execution slots, not processes or threads.
- Each worker = a separate tmux window running a bash command.
- Agent (LLM) orchestrates via bash tool calls — spawn, read, kill workers.

### Commands
| Command | Action |
|---|---|
| `/worker <name> <cmd>` | Spawn tmux window `<name>` running `<cmd>` |
| `/workers` | List all tmux windows in session |
| (LLM tool) `tmux capture-pane -p -t <name>` | Read worker output |
| (LLM tool) `tmux kill-window -t <name>` | Kill worker |

### Requirements
- Must be running inside **tmux** (checks `$TMUX` env var).
- Without tmux, worker spawn fails with "Not in tmux — can't spawn worker."

### LLM-side pattern (from system prompt)
```
Spawn:   bash → tmux new-window -n <name> 'cmd 2>&1 | tee /tmp/<name>.log'
Read:    bash → tail -f /tmp/<name>.log  OR  tmux capture-pane -p -t <name>
Kill:    bash → tmux kill-window -t <name>
List:    bash → tmux list-windows
```

### Limitations
- Workers are **dumb bash processes**, not agents — no LLM, no tool use, no decision-making.
- LLM must poll for results manually.
- No structured inter-worker communication or dependency management.
- Single LLM context window manages all workers — doesn't scale to many concurrent tasks.

---

## Sub-Agents: None

Mix has **no sub-agent architecture**:

1. **No LLM-in-LLM calls** — the agent loop (`src/24_agent_loop_*.sh`) calls the API once per iteration. No nesting.
2. **No agent delegation** — `/build` prompt explicitly says "No sub-agents" (line 108 in `25_repl_commands.sh`).
3. **Workers are not agents** — they're plain bash commands. Can't reason, use tools, or call the LLM.

### What this means
- All reasoning, planning, tool selection happens in **one LLM context**.
- Complex multi-step work is sequential in the agent loop (plan → act → observe → repeat).
- Parallelism is limited to **fire-and-forget bash commands** (builds, tests, watches) while the main agent continues working.

---

## Architecture Diagram

```
┌─────────────────────────────┐
│         LLM API             │
│   (single context window)   │
└──────────┬──────────────────┘
           │ tool calls
           ▼
┌─────────────────────────────┐
│      Agent Loop (REPL)      │
│   src/24_agent_loop_*.sh    │
│                             │
│   Tools: bash, read, edit,  │
│   create, search, list      │
└──────┬──────────────────────┘
       │
       ├──► bash (direct commands)
       │
       ├──► tmux new-window ──► Worker 1 (dumb bash)
       ├──► tmux new-window ──► Worker 2 (dumb bash)
       └──► tmux new-window ──► Worker N (dumb bash)
```

---

## Source Files
- `src/03_system_prompt_*.sh` — worker docs in system prompt
- `src/25_repl_commands.sh` — `/worker`, `/workers` implementation
- `src/26_banner.sh` — worker hint in banner
- `src/02_tmux_bootstrap.sh` — tmux session setup
