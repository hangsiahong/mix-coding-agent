# Design Philosophy — Why Mix Works

Mix is a 5240-line terminal coding agent that punches far above its weight. This document explains the thinking behind every major decision — not just what we chose, but what we rejected and why.

---

## 1. Why Bash

**Zero install.** Bash ships on every Linux, macOS, WSL, and most containers. No runtime to download, no version mismatch, no `nvm`/`pyenv`/`rustup` dance. User runs `curl | bash` and it works — that's the promise.

**Direct system access.** A coding agent's core job is running commands, editing files, checking git. Bash does this natively — no `child_process.spawn()`, no `subprocess.run()`, no FFI. One line, not five. Need to run a test? `bash -c "$cmd"`. Need to edit a file? `sed` or heredoc. Need git status? `git status`. Zero impedance mismatch.

**Transparent.** Every user can read bash. No compiled binary to decompile, no transpilation step, no `node_modules` black hole. Bug in the agent? Open the file, read it, fix it. The source IS the binary (after `cat`).

**Startup speed.** `source` 38 files in ~50ms. No JIT warmup, no module resolution, no lazy loading. Instant REPL, instant feedback loop.

**Self-hosting.** Mix was built by mix. Every feature, every fix, every test was done through the agent itself. Bash made this possible — the agent edits its own `.sh` source files, rebuilds with `./build.sh`, and tests with `bats`. No separate build toolchain needed.

### Bash downsides and mitigations

| Concern | Mitigation |
|---|---|
| No data structures (arrays, dicts, nested objects) | python3 inline for JSON — history, tool args, session state |
| No error handling | `set -euo pipefail` + EXIT trap + streak detection |
| String manipulation gets ugly | python3 one-liners for anything beyond `${var#pattern}` |
| No module system | 38 files with numeric prefixes, loaded by `cat` in order |
| Testing story | bats-core — bash-native TAP testing, 166 tests |
| Scale ceiling | Modular structure enforced: one concern per file, ~20 lines per function |

---

## 2. Why Python3 (Not jq, Not Node, Not Perl)

python3 handles JSON natively via `json` module. This is the ONLY reason python3 exists in the stack — bash has no JSON parser, and every coding agent must manipulate JSON constantly (API responses, tool arguments, history arrays, session state).

| Tool | Rejected Because |
|---|---|
| **jq** | Extra dependency. Great for one-off queries, terrible for building/transforming complex nested JSON. No variables across pipes. Escaping nightmare inside bash heredocs. Can't append to arrays in-place. |
| **node** | Requires Node.js installed. 200MB+ runtime for `JSON.parse`. Then you're maintaining two language ecosystems. |
| **perl** | JSON module not in core. `JSON::PP` is version-dependent. Perl regex is powerful but the JSON story is weak. |
| **yq** | Not installed anywhere by default. jq's problems plus YAML parsing we don't need. |

python3 wins because it's already on every system AND has `json`, `base64`, `sys`, `os` in stdlib. No pip, no venv, no packages. Just `python3 -c 'import json,sys;...'`.

### The stdin pipe pattern

```bash
# JSON append — python3 reads stdin, writes temp file
python3 -c "
import json, sys
data = json.load(sys.stdin)
data.append({'role':'user','content':"""$escaped_input"""})
json.dump(data, open('$tmpfile','w'))
" < "$HISTORY_FILE"
```

stdin pipe avoids ARG_MAX (shell argument length limit). Temp file avoids escaping hell. One process per operation, zero daemons, zero background services.

---

## 3. Why cat Compilation (Not a Build System)

```bash
cat src/providers/*.sh src/0*.sh src/1*.sh src/2*.sh > mix.compiled
```

That's the entire build pipeline. No webpack, no cargo, no Makefile. `cat` concatenates numbered files in order. Files are numbered so function definitions appear before their call sites — bash requires this.

The result is a single 5240-line executable. No bundling step, no tree-shaking, no optimization pass. What you read is what runs. The compiled binary IS the debuggable source.

### Why this matters

- **Zero-config build.** New developer clones repo, runs `./build.sh`, done.
- **No version skew.** No `package-lock.json`, no `Cargo.toml`, no dependency resolution.
- **Auditable.** `cat mix.compiled | less` — read the entire agent in one file.
- **Distributable.** One file, `curl | bash` install, no archive extraction.

---

## 4. Why Regex Repo Map (Not AST)

AST parsers require tree-sitter (compiled binary per language) or language servers (heavy daemons running in background). Regex `grep` patterns get 80% of the value at 5% of the code:

```bash
grep -En '^\s*(function\s|def\s|fn\s|pub\s+fn|func\s|class\s|export\s|const\s|let\s)'
```

Result: ~1200 tokens of code structure injected into the system prompt. The LLM sees function signatures, variable declarations, class outlines — enough to navigate without reading files. Eliminates 2-3 "read this file" turns per task.

### What we get vs what we miss

| Regex captures | AST-only |
|---|---|
| Function/method names | Cross-file type inference |
| Class/struct/interface names | Call graph |
| Import/export lines | Dead code detection |
| Variable declarations at top level | Scope analysis |
| Comments (TODO, FIXME) | Semantic understanding |

The tradeoff is intentional. Mix is a coding agent, not an IDE. Navigation matters more than analysis.

---

## 5. Context Engineering — The Real Innovation

Most coding agents treat the LLM as a chatbot with tool access. Mix treats context as a **managed resource** with explicit budgets, caching layers, and compaction strategies.

### The three caches

| Cache | Size | Survives Compaction? | Purpose |
|---|---|---|---|
| **Repo map** | ~1200 tokens | Yes (injected fresh each call) | Code structure — eliminates orientation turns |
| **File cache** | ~3000 chars (8 files, ~1000 tokens) | Yes (separate from history) | File contents — eliminates re-reads after compaction |
| **History** | Unlimited → auto-compacted | No (compacted to summary + last 10 messages) | Conversation — the working memory |

### Why this matters

Without these caches, a compacted agent loses all orientation. It must re-read files, re-scan the repo, re-learn the project. Each compaction costs 3-5 turns of pure recovery. With caches, the agent picks up exactly where it left off — repo structure and file contents survive the compaction boundary.

### Compaction strategy

When history exceeds `CTX_TOKENS` (default 131072), `compact_history()` sends old messages to the LLM for summarization, keeps the last 10 verbatim. The summary replaces N messages with ~500 tokens. File cache + repo map remain untouched — the agent never loses its bearings.

### Session persistence

On exit, `session_save()` writes file cache + repo map + env info + config to `.agent/session.json`. On next startup, `/resume` restores it. The agent "remembers" your project across sessions — no re-orientation needed.

---

## 6. The Edit System — Why Four Strategies

LLMs generate imperfect edit instructions. Mix doesn't give up on a bad `old_text` match — it escalates through four strategies:

1. **Exact match** — `old_text` found verbatim. Apply directly.
2. **Fuzzy match** — whitespace-normalized comparison. Catches indentation differences.
3. **Indent-normalized** — strips leading whitespace, matches content, re-applies original indent.
4. **Anchor match** — first + last line as anchors, matches everything between.

If all four fail, Mix shows `[SUGGESTION]` — surrounding lines from the file — so the LLM self-corrects in one turn without re-reading the file.

### Why this matters

A single failed edit costs 2-3 turns (read file → retry edit → verify). With four strategies + suggestion, the success rate is ~95% on first attempt. Over a long session, this saves dozens of turns and thousands of tokens.

---

## 7. Safety Without Paralysis

Mix uses a 4-tier risk scoring system for bash commands:

| Level | Behavior | Examples |
|---|---|---|
| **BLOCKED** | Never runs, no override | `rm -rf /`, fork bombs, `:(){ :\|:& };:` |
| **HIGH** | Requires explicit user confirmation | `rm -rf dir/`, `sudo rm`, `dd` |
| **MED** | Auto-confirmed in yolo mode, shows notice otherwise | `npm install`, `apt get`, `pip install` |
| **LOW** | Runs silently | `ls`, `cat`, `grep`, `git status` |

The key insight: most commands are LOW risk. Only ~5% of commands need confirmation. The system doesn't interrupt flow for safe operations but catches destructive ones before they run.

### Defense in depth

1. **Risk scoring** — pattern-matches command string
2. **Diff preview** — shows colored diff before edit_file applies
3. **Git auto-commit** — every edit committed immediately, `/undo` reverts
4. **Auto-verify** — syntax/lint/typecheck after every edit_file/create_file
5. **Trusted rc only** — only `~/.mix/rc.sh` auto-sourced, never project-local `.agent/rc.sh`

---

## 8. Caveman Mode — Token Efficiency as a Feature

LLMs default to verbose — "Sure! I'd be happy to help you with that." Caveman mode strips this noise at the system prompt level:

| Level | Effect |
|---|---|
| `ultra` | Edits only. No explanations. No text between tool calls. |
| `full` | Terse fragments. "Bug in auth. Fix:" — no filler, no pleasantries. |
| `lite` | Short sentences allowed. Slightly more context. |
| `off` | Normal LLM output. |

Why this matters: a verbose response wastes 200-500 tokens per turn. Over 50 turns, that's 10,000-25,000 tokens of noise — 10-20% of a typical context window. Caveman mode recovers that budget for actual work.

---

## 9. Extensibility Without Complexity

Three extension mechanisms, each solving a different problem:

### Skills (markdown files)

Drop a `.md` file in `~/.mix/skills/`, load with `/skill <name>`. Injected into system prompt. Pure context — teaches the LLM new behaviors without touching code.

**When to use**: domain-specific instructions ("always write tests for Go code", "use conventional commits"), workflow patterns ("after every edit, run the linter").

### Extensions (bash plugins)

Drop a `.sh` file in `~/.mix/extensions/` or `.mix/extensions/`. Convention hooks: `_init`, `_cmd`, `_tool`, `_on_edit`, `_on_create`, `_on_bash`, `_on_session`, `_on_shutdown`.

**When to use**: behavioral changes that need code — auto-lint on save, custom REPL commands, project guards, notification hooks.

### Providers (bash modules)

Drop a `.sh` file in `src/providers/`. Implements auth flow, API headers, model list, streaming setup.

**When to use**: adding a new LLM backend (Anthropic, OpenAI, local models).

### Why convention over configuration

No config file, no plugin manifest, no registration step. A function named `myext_on_edit` is automatically called after edits. A file in `~/.mix/skills/` is automatically available. This makes the system discoverable — read the convention, write the code, it works.

---

## 10. Why Not a "Real Language" Rewrite

**You don't need it.** Mix does 5 things: call API, parse response, run tools, manage history, display output. That's `curl` + `python3` JSON + bash I/O. A Rust rewrite would be 10x the code for the same result. A TypeScript rewrite adds a 200MB `node_modules` tree.

**The constraint is the feature.** Bash forces simplicity. No abstract class hierarchies, no dependency injection frameworks, no ORM. Each file does one thing. Each function is ~20 lines. The entire codebase is auditable in an afternoon.

**I/O-bound, not CPU-bound.** The bottleneck is always API latency (500ms-5s per call) and file I/O. Bash handles I/O just fine — it's been doing it for 30 years. No garbage collector, no JIT warmup, no event loop overhead.

**Self-hosting proof.** 5240 lines, 38 files, 166 tests, running non-stop for weeks building itself. The agent that wrote these words is the agent described by them. If bash couldn't handle it, it would have failed long before reaching this paragraph.

---

## 11. Parallelism Within Constraints

Bash has no native async/await. Mix works around this with a pragmatic pattern:

### Read-only tool batching

When the LLM returns multiple read-only tools (read_file, list_files, search_files), Mix runs them concurrently in subshells, writes results to a temp batch directory, then appends all results in one history flush. This cuts "read 5 files" from 5 sequential API round-trips to 1 parallel batch.

### Workers and subagents

- **`/worker <name> <cmd>`** — runs a bash command in a tmux window. Good for long-running builds, watches, servers.
- **`/subagent <name> <task>`** — spawns an independent LLM agent in tmux. Good for parallel research, background refactoring, independent tasks.
- **`/afk`** — sends task to background, notifies via Telegram when done, user approves plan remotely.

### Why not full async

Full async (like Node.js event loop) would add complexity for marginal gain. The API call is the bottleneck (~2s), not tool execution (~50ms). Parallel read-only batching addresses the real bottleneck without rearchitecting the entire agent loop.

---

## 12. The Memorybank — Compounding Knowledge

Three-layer wiki architecture:

| Layer | Mutability | Purpose |
|---|---|---|
| `raw/` | Read-only | Immutable sources. Never modified by agent. |
| `memorybank/` | Agent-owned | LLM-maintained markdown. Richer every session. |
| `AGENTS.md` | Co-evolved | Schema, conventions, domain rules. |

The memorybank turns every session into a permanent artifact. Today's debugging insight becomes tomorrow's solution page. The agent files its own findings, cross-references related pages, updates the index. Knowledge compounds.

### Operations

- **INGEST**: new source → summarize → create entity/concept pages → update index → log entry
- **QUERY**: question → read index → find pages → synthesize answer → file good answers as new pages
- **LINT**: health-check → find contradictions, orphans, gaps → fix or flag

### Why this matters for a coding agent

Without memorybank, every session starts from zero. With it, the agent builds institutional knowledge: which modules are fragile, which patterns caused bugs, which solutions worked. Session 100 is smarter than session 1 because it has 99 sessions of context.

---

## 13. Spec-Driven Development (Cavekit)

`/spec` defines features with structured sections:

| Section | Purpose |
|---|---|
| §G Goal | What we're building |
| §C Constraints | Hard boundaries |
| §I Interfaces | API surface, file schemas |
| §V Invariants | Must-never-break rules |
| §T Tasks | Ordered implementation steps |
| §B Bugs | Found during implementation |

`/build` executes tasks in order. `/check` detects drift between spec and code (zero writes). This gives the LLM a structured plan it can follow incrementally, rather than trying to implement everything in one shot.

### Why structured specs beat freeform prompts

A freeform "implement X" prompt has no checkpoints. The LLM either succeeds or fails as a monolith. Structured specs break work into verifiable steps — each task is a mini-contract with clear completion criteria. If the agent drifts, `/check` catches it.

---

## 14. Design Principles Summary

| Principle | Manifestation |
|---|---|
| **Zero surprises** | Git auto-commit, diff preview, risk scoring, auto-verify |
| **Recover fast** | 4-strategy edit matching, [SUGGESTION] on failure, self-healing bash |
| **Context is precious** | File cache survives compaction, repo map auto-injected, session persistence |
| **Noise is waste** | Caveman mode, smart bash truncation, token tracking |
| **Extensible by convention** | Skills (markdown), extensions (hooks), providers (modules) |
| **Compound knowledge** | Memorybank wiki, global memory, solution pages |
| **Small sharp tools** | 7 tools, each does one thing well |
| **Self-hosting** | Mix builds mix, tests mix, documents mix |

---

## Decision Record

| Decision | Chose | Rejected | Why |
|---|---|---|---|
| Primary language | Bash | Rust, TypeScript, Python | Zero install, direct system access, self-hosting |
| JSON handling | python3 inline | jq, node, perl | Stdlib only, no pip, already everywhere |
| Build system | cat | Make, webpack, cargo | Zero config, source = binary |
| Code structure | Regex grep | tree-sitter, LSP | 80% value, 5% code, zero deps |
| Streaming | python3 urllib | Node streams, Go SSE | One-liner SSE parser, no extra runtime |
| Plugin system | Convention hooks | Event bus, middleware | Discoverable, no registration |
| Context management | 3-layer cache | Flat history | Survives compaction, saves turns |
| Risk model | 4-tier scoring | Boolean allow/deny | Safety without paralysis |
| Test framework | bats-core | shunit2, shelltestrunner | Bash-native, TAP compatible, widely used |
| Distribution | Single file | npm package, Docker, Homebrew | curl \| bash, no ecosystem lock-in |
