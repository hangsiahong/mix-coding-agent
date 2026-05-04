# Token Tracking

## Problem
No visibility into API token consumption during a session. Users can't tell how much context budget remains or what the session cost.

## Solution
Session-scoped token counters initialized at startup, updated per API call, displayed in TUI.

### Implementation

#### Counters (`src/01_config.sh`)
- `_SESSION_PROMPT_TOKENS=0`
- `_SESSION_COMPLETION_TOKENS=0`
- `_SESSION_API_CALLS=0`

#### Extraction (`src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh`)
- From non-streaming API response JSON: `d.get("usage",{}).get("prompt_tokens",0)` and `.get("completion_tokens",0)`.
- Streaming responses don't return `usage` field (API limitation). Only non-streaming calls tracked.

#### Display (`src/20_context_window_bar.sh`)
- `ctx_bar()` prints second line with session stats when `_SESSION_API_CALLS > 0`.
- Format: `calls:N prompt:N completion:N total:N`

#### `/stats` command (`src/25_repl_commands.sh`)
- Shows: API calls, prompt/completion/total tokens, tools used count, history message count.

## Impact
- Users can monitor cost and budget during long sessions.
- Helps decide when to `/compact` or `/flush`.
