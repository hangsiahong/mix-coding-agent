# Copilot Provider

## Overview
GitHub Copilot provider for mix coding agent. Uses device-flow OAuth to get short-lived API tokens, then hits `api.githubcopilot.com` which is fully OpenAI-compatible.

## Auth Flow
1. `POST github.com/login/device/code` → `device_code` + `user_code`
2. User visits `https://github.com/login/device`, enters `user_code`
3. Poll `POST github.com/login/oauth/access_token` → `github_token` (persisted)
4. `GET api.github.com/copilot_internal/v2/token` → `copilot_token` (30min TTL, cached in `/tmp`)
5. `Bearer copilot_token` on `api.githubcopilot.com/chat/completions`

## Config
```
PROVIDER=copilot
MODEL=gpt-4o   # or claude-sonnet-4-20250514, o3, etc.
```

## Files
- `~/.mix/copilot_github_token` — persisted GitHub OAuth token (step 3)
- `/tmp/mix-copilot-api-token` — cached Copilot API token (step 4, auto-refreshes at 25min)
- `src/providers/copilot.sh` — provider implementation

## Provider Hooks
- `copilot_get_api_key()` — auto-refreshes short-lived token
- `copilot_extra_headers_json()` — returns JSON with Editor-Version, Openai-Organization headers
- `copilot_activate()` — sets BASE_URL, PROVIDER, MODEL
- `copilot_login()` — interactive device-flow OAuth
- `copilot_list_models()` — lists available models with capabilities

## Usage
```
/provider copilot login    # first time: authenticate
/provider copilot          # activate
/provider copilot models   # list available models
/model claude-sonnet-4-20250514  # switch model
```

## Integration
- `call_api()` and `call_api_stream()` both check for `${PROVIDER}_get_api_key` and `${PROVIDER}_extra_headers_json`
- Streaming uses `EXTRA_HEADERS` env var to pass JSON to python3 urllib block
- Non-streaming uses python3 to parse extra headers and add to curl args
- Provider auto-loads at startup if `AGENT_PROVIDER=copilot` is set
