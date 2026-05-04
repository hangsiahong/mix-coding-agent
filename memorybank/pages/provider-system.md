# Provider System

## Architecture

Pluggable API backends. Providers override auth, headers, and endpoints. Hot-switch at runtime via `/provider`.

```
01_config.sh → _load_provider() → source src/providers/<name>.sh
            → ${PROVIDER}_activate()  (set BASE_URL, MODEL, API_KEY)
            → ${PROVIDER}_get_api_key()  (called by 12, 16, 18 — auto-refresh tokens)
            → ${PROVIDER}_extra_headers_json()  (called by 18 streaming)
```

## Defaults File

`~/.mix/defaults` — persisted provider + model + base URL. Loaded at startup, overridden by env vars.

```
PROVIDER=default
MODEL=koompiclaw
BASE_URL=https://ai.koompi.cloud/v1
```

## Available Providers

### default
- KOOMPI Cloud proxy. OpenAI-compatible.
- Auth: KCONSOLE_API_KEY env var or `~/.mix/api_key`.
- Models: glm-5, koompiclaw, others via /model.

### copilot
- GitHub Copilot subscription. OpenAI-compatible endpoint.
- Auth: device-flow OAuth → github_token → copilot_token (30min TTL, auto-refresh at 25min).
- Models: gpt-4o, claude-sonnet-4-20250514, o3, etc.
- Files: `~/.mix/copilot_github_token`, `/tmp/mix-copilot-api-token`
- Hooks: `_activate`, `_login`, `_get_api_key`, `_extra_headers_json`, `_list_models`, `_validate_model`
- Usage: `/provider copilot login` → `/provider copilot` → `/model claude-sonnet-4-20250514`

## Adding Providers

Drop `<name>.sh` in `src/providers/` (built-in) or `~/.mix/providers/` (user). Must implement:
- `${name}_get_api_key()` — returns API key (auto-refresh if needed)
- `${name}_activate()` — sets BASE_URL, PROVIDER, MODEL
- Optional: `_list_models`, `_validate_model`, `_extra_headers_json`, `_login`

## Env Vars

| Var | Purpose |
|---|---|
| `KCONSOLE_API_KEY` | Default provider API key |
| `AGENT_PROVIDER` | Override provider at startup |
| `AGENT_MODEL` | Override model at startup |
| `MIX_YOLO` | Auto-confirm all (1=yes) |
| `MIX_NO_TMUX` | Skip tmux bootstrap |
| `CAVEMAN_MODE` | off/lite/full/ultra |
| `AGENT_MODE` | fast/deep/plan |
| `MAX_TURNS` | Max tool-use iterations (default: 50) |
| `MAX_HIST_MSGS` | Compact threshold (default: 60) |
| `CTX_TOKENS` | Model context window size (default: 131072) |
| `STREAM` | Enable streaming (default: true) |
