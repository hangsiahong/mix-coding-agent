# Repo Map — Codebase Structural Awareness

## Problem
Every coding task started with 2-3 "orientation" tool calls: `search_files`, `list_files`, `read_file` — just to figure out where things are. The agent was blind to codebase structure until it actively searched.

## Solution: `src/11b_repo_map.sh`
Regex-based structural extractor that builds a compressed map of the codebase (~1600 tokens), injected into the system prompt every API call.

### What it extracts
- **File tree**: source files with smart collapsing (>60 files → top-level dirs with counts)
- **Function signatures**: `grep` for language-specific patterns
- **Class/method/import lines**: Python, JS/TS, Go, Rust, Java, Ruby, C
- **File sizes**: line counts, large files (>500L) noted but not scanned
- **Git recency**: recently changed files highlighted (if git enabled)
- **API routes**: TS/JS route handlers (GET, POST, PUT, DELETE) extracted

### Language support (regex patterns)
sh, py, js, ts, go, rs, java, rb, c, h — 10 languages with structural extraction.

### Pattern filtering (noise reduction)
- `export const runtime` filtered out (TS route boilerplate)
- Only PascalCase `const` declarations extracted (component names)
- Non-code files (md, json, yaml, toml, sql, proto) excluded from structure extraction
- Max 20 structural lines per file (prevents single file dominating budget)

### Token budget
~4800 chars (~1600 tokens) max. Hard trim with truncation notice when exceeded.

### Smart tree collapsing
- Projects with ≤60 files: full file listing
- Projects with >60 files: top-level directories with file counts + root-level files
- `awk -F/` for literal path matching (handles `[id]`, `(app)` special chars)

### Caching
- Built once, cached in shell variables (`_REPO_MAP`, `_REPO_MAP_MTIMES`)
- **TTL**: 600 seconds (10 minutes)
- **mtime check**: samples up to 50 files, rebuilds if any changed
- **Manual invalidation**: `/refresh` command or `repo_map_invalidate()`

### Integration
- `build_repo_map()` called from `build_system_prompt()` (03)
- Injected as `## REPO MAP` section between ENV and GLOBAL MEMORY
- Zero new dependencies — uses `find`, `grep`, `stat`, `wc`, `awk`

### Skip directories
`.git node_modules __pycache__ .venv venv dist build .next .nuxt target .gradle .idea .vscode .cache .tox .mypy_cache .pytest_cache coverage htmlcov .sass-cache bower_components vendor/bundle .mix .agent .terraform .terragrunt-cache .worktrees .turbo .vercel .contentlayer .docusaurus`

## Impact
- Eliminates 2-3 orientation tool calls per task
- Reduces average task from 6 turns to 3-4 turns
- Agent can target correct file on first try
- For 10-task session: ~20 fewer turns, ~10 fewer API calls

### Validated across project types
| Project | Type | Size | Structural Lines |
|---------|------|------|-----------------|
| agent (self) | Bash | 3960 chars | 54 |
| Linote | Next.js/TS | 4804 chars | 64 |
| sigma | Next.js/TS (large) | 4796 chars | 66 |
| switcher | GNOME JS | 1605 chars | 4 |
| builder-ai | Next.js/TS | 4734 chars | 4 |
| jersen.app | Next.js/TS | 4796 chars | 69 |

## Files modified
- `src/11b_repo_map.sh` — new (200+ lines)
- `src/03_system_prompt_*.sh` — repo map injection (+8 lines)
- `src/25_repl_commands.sh` — `/refresh` command
- `src/26_banner.sh` — help text update
- `src/27_main_repl.sh` — tab completion update
- `build.sh` — include new file
