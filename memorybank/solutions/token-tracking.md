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
- `_SESSION_CACHE_TOKENS=0`

#### Extraction
- **Streaming** (`src/18_streaming_api_call.sh`): `usage.prompt_tokens_details.cached_tokens` extracted from SSE usage chunk. Format: `USAGE:pt:ct:cache`
- **Non-streaming** (`src/24_agent_loop_one_user_turn_multi_turn_tool_use_final_answer.sh`): `usage.prompt_tokens`, `.completion_tokens`, `.prompt_tokens_details.cached_tokens` from JSON response
- Backward compatible with old 2-field `USAGE:pt:ct` format (cache defaults to 0)

#### Display (`src/20_context_window_bar.sh`)
- `ctx_bar()` prints session stats line in purple (`38;5;183`) when `_SESSION_API_CALLS > 0`
- **Smart M/k formatting**: `_fmt_tok()` helper shows `5M` / `5k` / `500` based on magnitude
- **Cache token %**: `${cache_pct}% cached` shown in purple when provider returns cache data
- Format: `│ session: 112 calls, ~5M tokens used · 59% cached`

#### `/stats` command (`src/25_repl_commands.sh`)
- Shows: API calls, prompt/completion/total tokens, cache tokens (%), tools used, history message count.

## Impact
- Users can monitor cost and budget during long sessions.
- Helps decide when to `/compact` or `/flush`.
