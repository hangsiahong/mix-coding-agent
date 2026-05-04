# Why "Minimal" — The Answer

## The Question
> "mix is 2735 lines across 29 files. How is that minimal?"

## Short Answer
"Minimal" = **zero framework, zero runtime, zero install footprint**. 2735 lines of pure bash + inline python3 one-liners. No pip, no npm, no Docker, no TypeScript compiler. One binary, run it.

## The Numbers

| Metric | mix | Claude Code | Aider | OpenHands |
|---|---|---|---|---|
| **Dependencies** | bash, curl, python3 | Node.js + npm stack | Python + pip packages | Docker container |
| **Install size** | ~80KB (one binary) | ~200MB+ node_modules | ~50MB+ venv | ~2GB+ Docker image |
| **Install command** | `curl \| bash` | `npm install -g` | `pip install aider-chat` | `docker pull` |
| **Runtime** | bash interpreter | Node.js runtime | Python + packages | Full container |
| **Languages** | bash + inline python3 stdlib | TypeScript | Python | Python in Docker |
| **Boot time** | instant | ~2s | ~3s | ~10s+ |

## Line Budget Breakdown

| Component | ~Lines | Purpose |
|---|---|---|
| REPL + 25 slash commands | 850 | /spec /build /check /afk /worker /provider /skill /undo /paste etc |
| Tool execution + UX | 360 | 7 tools, risk scoring, diff preview, git commit, test runner |
| Streaming API + parsing | 280 | SSE parser, network retry, RAW/TC/TEXT protocol |
| Agent loop | 130 | Multi-turn tool use, plan mode, memorybank auto-append |
| System prompt builder | 145 | Wiki pattern, cavekit, global memory, skills injection |
| History + compact | 135 | JSON via python3 stdin pipe, LLM summarization |
| Config + providers | 120 | Multi-provider, defaults persistence, hot-switch |
| REPL UI (readline, paste) | 220 | Tab-complete, Ctrl+V paste, Ctrl+E editor, bracketed paste |
| Telegram + AFK | 85 | Bot setup, inline buttons, 2h poll |
| Misc (banner, env, spinner, etc) | 110 | Environment detection, context bar, tmux status |

## The "Minimal" Claim

1. **Minimal surface area**: 7 tools. Read, write, edit, search, list, bash, global memory.
2. **Minimal dependency tree**: bash + curl + python3 (stdlib). Already on every machine.
3. **Minimal abstraction**: No middleware, no plugin compilation, no config DSL. System prompt is a bash string. API call is curl.
4. **Minimal attack surface**: No npm/pip supply chain, no container, no daemon, no background service.
5. **Minimal install**: `curl | bash`. Two commands.

## Why bash + python3

python3 used exclusively for JSON (bash has none). Every call: `python3 -c 'import json,sys;...'`. Stdlib only, no pip, no venv.

bash constraint eliminates "works on my machine" problems. python3 constraint eliminates pip dependency hell.
