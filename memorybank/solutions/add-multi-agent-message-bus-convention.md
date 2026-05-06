# Task: Add multi-agent message bus convention
Date: 2024-05-18

## Result
Subagents spawned via `/subagent` (or the `spawn_subagent` tool) run in isolated tmux windows with no shared state, making coordination difficult. Added a file-based message bus convention. Subagents now use the `.agent/bus/` directory to write and read shared state. Updated the system prompt to explicitly teach this pattern to the LLM, and modified the `spawn_subagent` tool to auto-create the directory and hint at its usage in the success response. No daemons required, just Unix file conventions.

## Files Modified
- `src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh`
- `src/13_tool_execution.sh`