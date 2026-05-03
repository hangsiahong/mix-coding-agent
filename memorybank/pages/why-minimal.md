# Why "Minimal" — The Answer

## The Question
> "You say mix is a super minimal coding agent, but it's over 1,500 lines. How is that minimal?"

## Short Answer
"Minimal" ≠ "short". Minimal = **zero framework, zero runtime, zero install footprint**. The 1,500 lines are pure bash. No pip, no npm, no Docker, no TypeScript compiler. Copy one file, run it.

## The Numbers

| Metric | mix | Claude Code | Aider | OpenHands |
|---|---|---|---|---|
| **Dependencies** | bash, curl, python3 | Node.js + npm stack | Python + pip packages | Docker container |
| **Install size** | ~50KB (one file) | ~200MB+ node_modules | ~50MB+ venv | ~2GB+ Docker image |
| **Install command** | `curl \| bash` | `npm install -g` | `pip install aider-chat` | `docker pull` |
| **Runtime** | bash interpreter you already have | Node.js runtime | Python + 50+ packages | Full container |
| **Languages** | bash + inline python one-liners | TypeScript | Python | Python in Docker |
| **Boot time** | instant | ~2s | ~3s | ~10s+ (container) |

## What Those 1,500 Lines Actually Do

~1,300 lines of actual code, broken down:

- **Core agent loop** (~200 lines): multi-turn tool use, streaming, response parsing
- **5 tools** (~250 lines): bash, read_file, create_file, edit_file, search_files — the minimum viable set
- **Safety** (~80 lines): risk scoring, blocked commands, user confirmation
- **Streaming API** (~140 lines): SSE parsing, live token display, context window bar
- **History management** (~100 lines): auto-compact, JSON append/truncate
- **REPL & commands** (~350 lines): 15+ slash commands, tmux workers, subagents
- **Config & boot** (~100 lines): env detection, tmux bootstrap, git setup
- **System prompt** (~130 lines): rebuilt each call, caveman mode injection

No line is framework tax. Every line is **the product**.

## Why python3 Is There

python3 is used exclusively for **JSON parsing** (bash has no native JSON). Every call is a one-liner: `python3 -c 'import json,sys; json.load(sys.stdin)'`. No pip packages. No virtualenv. Just the stdlib that ships with every Linux/Mac.

## The "Minimal" Claim Decomposed

### 1. Minimal Surface Area
5 tools. That's it. Not 20, not 50. Read, write, edit, search, bash. Everything an LLM needs to code, nothing more.

### 2. Minimal Dependency Tree
```
bash    → ships with every OS
curl    → ships with every OS  
python3 → ships with every OS (used only for JSON)
```
That's the entire dependency graph. Three things already on your machine.

### 3. Minimal Abstraction Layers
No middleware. No plugin system. No config files. No build step. The system prompt is a bash string. The tool definitions are bash heredocs. The API call is `curl`. The response parser is `sed` + `python3 -c`.

### 4. Minimal Attack Surface
- No npm supply chain
- No pip dependency confusion
- No container escape
- No daemon running
- No background service
- One file, one process, one terminal

### 5. Minimal Install Friction
```bash
curl -fsSL URL | bash
mix
```
Two commands. No `brew install`, no `pip install`, no `docker pull`. You're coding.

## The Honest Take

1,500 lines of bash doing what Claude Code does in 100,000+ lines of TypeScript is **the point**. The bloat ratio is real. Bash is verbose — error handling, JSON parsing, string escaping all take more lines. But every line is visible, auditable, and modifiable with `vi`.

The "minimal" claim is about **complexity budget**, not line count. mix spends its complexity budget on the agent, not the framework around the agent.

## If Someone Pushes Back Further

**"But it's still 1,500 lines, not 500."**

True. Could it be smaller? Yes — strip streaming, strip tmux workers, strip subagents, strip caveman mode, strip risk scoring, strip auto-compact. You'd get ~400 lines. But then it wouldn't be *useful*. Minimal is the smallest thing that's still genuinely useful as a daily coding tool.

**"Why not Python then? Shorter and cleaner."**

Because then you need pip, venv, and a Python environment. bash+curl+python3-stdlib is a stricter constraint that eliminates an entire class of "works on my machine" problems.

**"Line count doesn't matter."**

Correct. What matters is: can you understand the whole thing in one sitting? With mix, yes. One file, top to bottom, linear execution. No jumping between 47 files in 8 directories. That's minimal.
