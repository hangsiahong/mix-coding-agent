# mix-coding-agent: Architecture Deep Dive

## What It Is

A single-file (~5169 lines compiled) terminal coding agent written in **bash + embedded Python3**. No Node.js, no pip packages, no build toolchain beyond `cat`. The entire agent is 35+ shell source files concatenated by `build.sh` into one executable `mix` binary.

**Philosophy**: Maximum capability, minimum dependencies. `bash`, `curl`, `python3` — that's it.

## Architecture Overview

```
build.sh ──concat──▶ mix (single executable)
                         │
    ┌────────────────────┼────────────────────┐
    │                    │                    │
  Boot Sequence     Agent Loop            REPL Layer
  (01→07)           (16→24)              (25→27)
```

### Build System

`build.sh` cats files in strict order. Order matters because:
1. **Providers** embedded first (so `copilot_activate` exists when `01_config.sh` calls it)
2. **Config** (`01_config.sh`) sets all globals: `API_KEY`, `MODEL`, `BASE_URL`, `PROVIDER`
3. **Session** (`11c_session.sh`) must come before `07_environment_detection.sh` (we hit this bug — `session_hint: command not found`)
4. **Main REPL** (`27_main_repl.sh`) must be last — it's the blocking loop

The compiled binary is self-contained. No source files needed at runtime.

### Boot Sequence (executed top-to-bottom on startup)

```
00_header.sh          set -uo pipefail (no set -e)
  ↓
providers/*.sh        Embedded (copilot.sh). Functions defined, not called.
  ↓
01_config.sh          Load API key (env → file → prompt). Set MODEL, BASE_URL, PROVIDER.
                      Load saved defaults from ~/.mix/defaults. Auto-load provider.
  ↓
02_mixrc.sh           Walk up from WORKDIR, find .mixrc, apply whitelisted keys.
                      Priority: env vars > .mixrc > defaults.
  ↓
04_project_local.sh   Source ~/.mix/rc.sh if exists (trusted, arbitrary code).
  ↓
04b_extension_system  Auto-load ~/.mix/extensions/*.sh and .mix/extensions/*.sh.
                      Call <name>_init() on each.
  ↓
11c_session.sh        Define session_save/load/apply/clear/hint functions.
  ↓
07_environment_detection.sh
                      detect_env() — git, node, python, docker, linters.
                      session_load 2>/dev/null  ← calls function from 11c
                      session_hint             ← shows "Previous session found"
  ↓
...remaining sources define functions, no top-level execution...
  ↓
27_main_repl.sh       EXIT trap, SIGINT handler, readline config, REPL loop.
```

### Agent Loop (per user turn)

```
run_agent(input)
  │
  ├─ compact_history()        Auto-compact if >MAX_HIST_MSGS
  ├─ append_text("user", input)
  │
  └─ while turn < MAX_TURNS:
       │
       ├─ start_spinner()
       ├─ call_api_stream()     ← Python3 SSE streaming via urllib
       │    │
       │    ├─ build_system_prompt()   ← rebuilt EVERY call (picks up config changes)
       │    │    ├─ Base prompt (TASK RULES, WORKERS, SKILLS, WIKI PATTERN)
       │    │    ├─ ENV_INFO injection
       │    │    ├─ Repo map (Aider-style, 4800 char budget)
       │    │    ├─ File cache (3000 char budget, 8 files max)
       │    │    ├─ Global memory (~/.mix/memory.md)
       │    │    ├─ Context budget warning (>60% used)
       │    │    ├─ SPEC.md injection (if present)
       │    │    ├─ Active skills content
       │    │    └─ Caveman mode compression rules
       │    │
       │    ├─ Build OpenAI-compatible payload
       │    ├─ Stream tokens to /dev/tty (live display)
       │    ├─ Post-stream markdown rendering (replaces raw with styled)
       │    └─ Return parsed: RAW: + TC: + TEXT: + USAGE: lines
       │
       ├─ If tool calls (TC: lines):
       │    ├─ PARALLEL: read_file, list_files, search_files (subshells)
       │    ├─ SEQUENTIAL: bash, edit_file, create_file (interactive confirm)
       │    │    ├─ Risk scoring (BLOCKED/HIGH/MED/LOW)
       │    │    ├─ Diff preview (edit_file)
       │    │    ├─ Auto-verify (syntax + lint + typecheck)
       │    │    ├─ Git add + commit (if git enabled)
       │    │    └─ Extension hooks (on_edit, on_create, on_bash)
       │    └─ Loop back (model sees tool results)
       │
       └─ If text response (TEXT: line):
            └─ Break loop, show final answer
```

## Key Subsystems

### 1. System Prompt Engineering (03_system_prompt.sh)

The system prompt is **rebuilt on every API call**. This is intentional — it picks up:
- Caveman mode changes mid-session (`/caveman ultra`)
- File cache updates (newly read files)
- Repo map rebuilds (TTL-based)
- Skill loading/unloading
- Config changes (model, provider)

**Token budget allocation** (rough):
- Base prompt: ~1500 tokens
- Repo map: ~1600 tokens (4800 chars)
- File cache: ~1000 tokens (3000 chars)
- Global memory: variable
- SPEC.md: variable (head -200)
- Skills: variable
- Context budget warning: conditional

### 2. Streaming (18_streaming_api_call.sh)

Pure Python3 SSE client using `urllib.request` (no requests, no httpx). Handles:
- Live token display to `/dev/tty`
- Tool call accumulation (delta chunks)
- Connection drops → automatic retry without streaming
- `Ctrl+C` cancellation (KeyboardInterrupt → graceful stop)
- Post-stream markdown rendering (erase raw, reprint styled)
- Usage tracking (prompt_tokens + completion_tokens)

### 3. File Edit System (13_tool_execution.sh → edit_file case)

4-tier matching strategy:
1. **Exact match** — `content.count(old_text) == 1`
2. **Fuzzy whitespace** — normalize trailing whitespace + line endings
3. **Indent-agnostic** — strip leading whitespace, match by line count
4. **Anchor match** — first + last line of old_text as anchors

On failure, emits `[SUGGESTION]` with context lines — helps model self-correct without re-reading.

### 4. Repo Map (11b_repo_map.sh)

Aider-inspired structural code awareness. Regex-based (no AST):
- Per-language patterns (sh, py, js/ts, go, rs, java, rb, c/h)
- 4800 char budget, 10-minute TTL
- Invalidates on mtime change (samples up to 50 files)
- Collapses to directory summaries when >60 files
- Shows recently changed files (git diff HEAD~5)

### 5. File Cache (11a_file_cache.sh)

Session-scoped content cache. **Survives history compaction**:
- Budget: 3000 chars, max 8 files, 400 chars/file
- Head/tail truncation for large files
- Mtime-based invalidation
- Injected into system prompt so model doesn't re-read

### 6. History Compaction (12_auto_compact_history.sh)

When history exceeds `MAX_HIST_MSGS` (default 60):
1. Send full history to LLM with summarization prompt
2. Extract structured summary (Task/Done/State/Context)
3. Keep last 10 messages verbatim
4. Replace: `[compacted summary] + last 10 msgs`

File cache + repo map persist independently — compaction doesn't lose awareness.

### 7. Session Persistence (11c_session.sh)

Save on EXIT, restore on `/resume`:
- Saves: env_info, provider/model/config, file_cache, repo_map, active_skills, last_input
- Validates: JSON integrity, CWD match, age < 7 days
- mtime check on restored file cache entries
- Repo map TTL still enforced (stale → rebuild)
- Never saves API_KEY

### 8. Extension System (04b_extension_system.sh)

Convention-based plugins. Drop `.sh` in `~/.mix/extensions/` or `.mix/extensions/`:
- `<name>_cmd()` — REPL commands (dispatched before built-in)
- `<name>_tool()` — custom tools (dispatched before "unknown" fallback)
- `<name>_on_edit/create/bash/session/shutdown` — lifecycle hooks
- Project overrides global (same filename wins)

### 9. Risk Scoring (14_risk_scoring.sh)

Pattern-based command risk assessment:
- **BLOCKED**: `rm -rf /`, fork bombs, kernel modules, cryptomining
- **HIGH**: `sudo`, `chmod 777`, `dd`, `mkfs`, force pushes — requires "YES" confirmation
- **MED**: `apt install`, `pip install`, `curl|bash` — auto-run if `AUTO_YES=true`
- **LOW**: everything else — auto-run

### 10. Self-Healing Bash (08_self_healing_bash_wrapper.sh)

On failure, attempts recovery:
- Permission denied → offer sudo retry
- Command not found → try `node_modules/.bin/` or `npx`
- Smart truncation: 50/50 head/tail + extract error lines from middle
- Failure diagnostics: pattern-based hints (missing module, port in use, disk full, etc.)

## Provider System

Pluggable API backends. Each provider is a `.sh` file defining hooks:
- `<name>_activate()` — set BASE_URL, MODEL, etc.
- `<name>_login()` — OAuth/device flow
- `<name>_get_api_key()` — return auth token
- `<name>_extra_headers_json()` — extra HTTP headers
- `<name>_validate_model()` — check model availability
- `<name>_list_models()` — list available models

**Copilot provider** (`providers/copilot.sh`): Full GitHub device-flow OAuth, token caching (30min TTL), model listing from `api.individual.githubcopilot.com`.

## Configuration Priority Chain

```
Environment variables (AGENT_MODEL, AGENT_BASE_URL, AGENT_PROVIDER)
         ↓ overrides
.mixrc (per-project, walks parent dirs, whitelisted keys only)
         ↓ overrides  
~/.mix/defaults (persisted by /model, /provider commands)
         ↓ overrides
01_config.sh hardcoded defaults (MODEL=glm-5, BASE_URL=https://ai.koompi.cloud/v1)
```

## Test Suite

151 bats tests covering:
- Extensions (262 lines) — load, dispatch, lifecycle hooks, project-overrides-global
- Session (27 tests) — save, load, apply, clear, validation, CWD check, age check
- Mixrc (231 lines) — whitelist enforcement, priority chain, parent dir walk
- File cache, risk scoring, response parsing, failure diagnostics

## Strengths

1. **Zero-config install**: `curl | bash` gives working agent. Copilot OAuth is one command.
2. **Context engineering**: File cache + repo map + global memory + SPEC.md injection = model never lost
3. **Build simplicity**: `cat` compiler. No transpilation, no bundling, no tree-shaking.
4. **Provider abstraction**: Clean plugin model. Copilot is a reference implementation.
5. **Self-healing**: Automatic diagnostics, recovery hints, failure streak detection.
6. **Edit precision**: 4-tier matching + suggestion context = very few re-reads needed.

## Weaknesses / Design Tensions

1. **Build order fragility**: Source file ordering is load-bearing. We already hit `session_hint: command not found` because `11c_session.sh` came after `07_environment_detection.sh` in `build.sh`. No validation of call-before-define.

2. **Python3 as shell glue**: Heavy use of inline `python3 -c` for JSON manipulation. Each call spawns a process. History operations (`append_raw`, `compact_history`) call python3 multiple times per turn. On slow systems this adds up.

3. **No structured error types**: Tools return strings. Errors are pattern-matched (`[[ "$result" == "[FAILED"* ]]`). No exit codes, no structured error objects. Makes programmatic error handling fragile.

4. **Single-threaded core**: Only read-only tools parallelize. Edit/create must be sequential (interactive confirmation). The parallel execution spawns subshells but writes to temp files then reads back sequentially.

5. **Context budget is soft**: The system prompt can grow unbounded if SPEC.md is large, many skills loaded, or global memory is long. No hard token limit enforcement — relies on LLM to be resilient.

6. **No tool schema validation**: Tool args parsed with `python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])'`. Missing/wrong key → silent empty string. No schema validation against `TOOLS_JSON`.

7. **History as JSON string**: `HISTORY` is a bash variable holding a JSON array. Operations on it require full serialization through python3. With 60 messages this gets slow.

8. **Security surface**: `~/.mix/rc.sh` is sourced (arbitrary code execution). `.mixrc` is whitelisted but sourced line-by-line in bash. Extensions are sourced. All trust-based, no sandboxing.

## Interesting Design Decisions

- **Caveman mode**: Not just system prompt compression — a philosophy. Three levels of response compression baked into the prompt itself. The model is told to be terse.

- **Post-stream markdown rendering**: Raw tokens stream to terminal, then the entire output is erased and re-rendered with syntax highlighting. Bold, code blocks, headers, bullets. User sees progressive output but final display is styled.

- **CAVEKIT spec system**: SPEC.md is injected into system prompt every call. The model can mutate it (`/spec bug:`, `/build`). Tasks track `. → ~ → x` status. Creates a feedback loop between agent and specification.

- **Global memory**: `~/.mix/memory.md` is injected every call. Cross-project, persistent. Updated via `update_global_memory` tool. The agent learns preferences and patterns across sessions.

- **Wiki pattern**: Three-layer knowledge management (raw/ → memorybank/ → AGENTS.md). Agent maintains its own documentation as a side effect of working. Compounding artifact.
