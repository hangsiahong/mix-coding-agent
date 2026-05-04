# Design Philosophy — Why This Stack

## Why Bash

**Zero install.** Bash is on every Linux, macOS, WSL. No runtime to download, no version mismatch, no `nvm`/`pyenv` dance. User runs `curl | bash` and it works.

**Direct system access.** Coding agent's core job is running commands, editing files, checking git. Bash does this natively — no `child_process.spawn()`, no `subprocess.run()`, no FFI. One line, not five.

**Transparent.** Every user can read bash. No compiled layer, no transpilation, no node_modules black hole. Bug in the agent? Open the file, read it, fix it.

**Startup speed.** `source` 38 files in ~50ms. No JIT warmup, no module resolution, no lazy loading dance. Instant REPL.

**Single binary compilation.** `cat src/*.sh > mix`. No bundler, no compiler, no build step. The "build system" is literally `cat`. 5240 lines, one file, done.

### What about the downsides?

| Concern | Mitigation |
|---|---|
| No data structures | python3 inline for JSON/arrays/dicts |
| Error handling | `set -euo pipefail` + trap handlers |
| String manipulation mess | python3 one-liners for anything beyond `${var#pattern}` |
| Testing | bats-core — bash-native TAP testing. 166 tests. |
| Maintainability at scale | Modular 38-file structure, one concern per file |

## Why Python3 (Not jq, Not Node, Not Perl)

python3 handles JSON natively via `json` module. Every other option has a fatal flaw:

| Tool | Problem |
|---|---|
| **jq** | Extra dependency. Great for one-off queries, terrible for building/transforming complex nested JSON (history array manipulation, tool result assembly). No variables across pipes. Escaping nightmare inside bash strings. |
| **node** | Requires Node.js installed. Heavy. JSON.parse/stringify is easy but then you're maintaining two languages. |
| **perl** | Available everywhere but JSON module not in core. `JSON::PP` exists but version-dependent. Syntax is write-only. |
| **yq** | Not installed anywhere by default. jq's problems plus YAML parsing we don't need. |
| **python3 -c** | Already on every system. `json`, `base64`, `sys`, `os` — all stdlib. Can handle arrays, nested objects, temp files, encoding in one expression. No pip needed. |

### The pattern

```bash
# JSON append to array — python3 reads stdin, outputs to temp file
python3 -c "
import json, sys
data = json.load(sys.stdin)
data.append({'role':'user','content':"""$escaped_input"""})
json.dump(data, open('$tmpfile','w'))
" < "$HISTORY_FILE"
```

stdin pipe avoids ARG_MAX. Temp file avoids shell escaping for complex data. One process, zero dependencies.

## Why Not a "Real Language" Rewrite

**You don't need it.** The agent does 5 things: call API, parse response, run tools, manage history, display output. That's curl + python3 JSON + bash I/O. A Rust rewrite would be 10x the code for the same result. A TypeScript rewrite adds a 200MB node_modules tree.

**The constraint is the feature.** Bash forces simplicity. No abstract class hierarchies, no dependency injection, no ORM. Each file does one thing. Each function is ~20 lines. The codebase is auditable in an afternoon.

**Proven at scale.** 5240 lines, 38 files, 166 tests, running non-stop for weeks building itself. Bash handles it fine because the workload is I/O-bound (API calls, file reads, git commands), not CPU-bound.

## Why Regex Repo Map (Not AST)

AST parsers require tree-sitter (compiled binary per language) or language servers (heavy daemons). Regex `grep` patterns get 80% of the value for 5% of the code:

```bash
# Function definitions — catches 90% of patterns across 10 languages
grep -En '^\s*(function\s|def\s|fn\s|pub\s+fn|func\s|class\s|export\s|const\s|let\s|var\s|type\s|interface\s|async\s)'
```

Result: ~1200 tokens of structure in system prompt. Eliminates 2-3 "read this file" turns per task. No parser to install, no grammar to maintain.

## Why No Framework

No React for TUI. No Express for API. No ORM for data. The agent is a **while loop**:

```bash
while (( _turns < MAX_TURNS )); do
  call_api_stream          # curl + SSE
  parse_resp               # python3 JSON
  process_tool_calls       # case/esac dispatch
done
```

Every "framework" feature (streaming, retry, parallel batching, session persistence) is ~50-200 lines of bash. Because the scope is narrow and the domain is well-defined, there's no abstraction leak to paper over.

## Summary

| Decision | Reason |
|---|---|
| Bash primary language | Zero install, direct system access, transparent, instant startup |
| Python3 inline only | JSON handling, stdlib only, no pip, stdin pipe for large data |
| cat compilation | No build step, no bundler, literal `cat` |
| Regex repo map | 80% of AST value at 5% of code, zero dependencies |
| No framework | Scope is narrow — while loop + curl covers it |
| bats testing | Bash-native, no extra language, TAP compatible |
