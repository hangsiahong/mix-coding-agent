# Task: Fix unescaped backticks in system prompt
Date: 2024-05-18

## Result
Whenever the agent chatted, the terminal outputted `duplicate session: test_env`. This was caused by unescaped backticks `` ` `` inside a double-quoted string (`base="..."`) in `src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh`. Because `build_system_prompt` is executed frequently (e.g. to compute token budget before the API call), bash evaluated the backticks and executed `tmux new-session -d -s test_env "mix"` on every turn, leaking the output to the REPL.

## Files Modified
- `src/03_system_prompt_rebuilt_on_each_call_to_pick_up_caveman_mode_changes.sh`