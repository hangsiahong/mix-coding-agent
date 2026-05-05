# Tmux Detached Workers

For advanced bug hunting and parallel orchestration, `mix` provides features to spawn background workers (`/worker`) and independent subagents (`/subagent` & `spawn_subagent` tool). 

### The Problem
Previously, when a background window was spawned via standard `tmux new-window`, tmux would forcefully shift the user's terminal focus to the newly created pane. This interrupted the user's view of the main `mix` REPL.

### The Solution
All background invocations across `mix` strictly enforce the **detached mode** flag (`-d`). 
- **Bash command:** `tmux new-window -d -n <name> <cmd>`
- **Session command:** `tmux new-session -d -s <session>`

### Agent Orchestration
This pattern is explicitly taught to the mix LLM itself via the system prompt (`src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh`). If the agent encounters a complex runtime bug that needs an interactive REPL or a live environment, it will proactively spin up its own isolated tmux session in the background, send keys to it, wait, and capture the output.

**System Prompt Directive:**
> **Testing/Orchestration:** For interactive REPL/bug-hunting, isolate via `tmux new-session -d -s test_env "mix"`, then `tmux send-keys -t test_env "/cmd" Enter`, sleep, and `tmux capture-pane -p -t test_env`. Never block the main agent.
