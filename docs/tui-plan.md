# mix-tui: Rich TUI for mix Agent

## Goal
Build a rich terminal UI as a separate script that wraps/enhances `mix` (the ~1k-line bash agent). `mix` stays untouched — TUI is pure presentation layer.

## Constraints
- `mix` is bash, ~1k lines. Don't bloat it.
- TUI must be a separate entrypoint: `mix-tui` (or `./mix --tui`)
- Keep current 3 deps: bash, curl, python3. TUI can add 1-2 more (python packages via pip).
- Must degrade gracefully — if TUI deps missing, fall back to current REPL.
- Headless mode still works: `./mix "query"` unchanged.

## Architecture

```
mix              → core agent (bash, minimal changes: --tui flag + structured output mode)
mix-tui          → TUI entrypoint (Python + textual/rich)
.agent/tui.d/    → user TUI extensions (keybindings, panels, themes)
```

### Data flow
```
┌─────────────┐    stdin/stdout     ┌──────────────┐
│   mix-tui   │ ◄────────────────► │     mix      │
│  (Python)   │   structured JSON  │   (bash)     │
│  renders UI │   over pipe        │  agent logic │
└─────────────┘                     └──────────────┘
```

- `mix-tui` spawns `mix --json` as subprocess
- `mix` in `--json` mode emits newline-delimited JSON events to stdout
- `mix-tui` reads events, renders panels, captures user input, sends to `mix` stdin

## Implementation Plan

### §T.1 — Structured output mode in `mix`
Status: .

Add `--json` flag to `mix`. When active:
- Emit JSON events to stdout instead of ANSI-formatted text
- Event types: `{"type":"token","content":"..."}`, `{"type":"tool_use","tool":"bash","args":{...}}`, `{"type":"tool_result","output":"...","exit":0}`, `{"type":"assistant_done"}`, `{"type":"error","msg":"..."}`, `{"type":"user_input","content":"..."}`
- Read user input from stdin (one JSON line per message: `{"type":"user_message","content":"..."}`)
- This is the bridge protocol. Minimal changes to `mix` — wrap existing printf/echo calls.

**Files:** `mix` (modify ~15-20 lines, add json_output() helper)

### §T.2 — TUI skeleton with textual
Status: .

Python script `mix-tui` using [textual](https://github.com/Textualize/textual) framework.

Panels:
```
┌─────────────────────────────────────────────────────┐
│ mix-tui                              model: glm-5   │  ← header bar
├─────────────────────────────────────────────────────┤
│                                                     │
│  Chat log (scrollable, markdown rendered)           │  ← main panel
│  - User messages (styled)
│  - Assistant messages (syntax highlighted)
│  - Tool calls (collapsible, diff previews)
│  - Tool results (collapsible, truncated)
│                                                     │
├─────────────────────────────────────────────────────┤
│ $ type here...                            [Send] ↵  │  ← input bar
├──────────────────┬──────────────────────────────────┤
│ Workers          │ Wiki                              │  ← status bar
│ ● build (running)│ memorybank: 12 pages              │
│ ○ test (done)    │ mode: fast | turns: 3/50          │
└──────────────────┴──────────────────────────────────┘
```

**Key features:**
- Syntax highlighting for code blocks (pygments/bat)
- Diff viewer for edit_file (green/red, like current show_edit_diff but prettier)
- Collapsible tool calls (expand/collapse with Enter)
- Status bar: model, mode, turn count, active workers, wiki page count
- Scrollable chat history with search (/)

**File:** `mix-tui` (single Python script, ~500-800 lines)

### §T.3 — Keybindings
Status: .

```
Ctrl+C          Cancel current generation
Ctrl+L          Switch model (fuzzy select from configured models)
Ctrl+P          Cycle previous prompts
Ctrl+K          Toggle command palette (like Pi)
/               Focus input (if in chat panel)
Escape          Toggle between chat and input focus
Tab             Toggle right sidebar (wiki/worker panels)
Ctrl+S          Steering: queue message while agent runs
Ctrl+R          Reload .agent/rc.sh and system prompt
q               Quit (with confirmation if agent running)
```

### §T.4 — Worker panel
Status: .

Right sidebar or bottom panel showing:
- Active tmux windows (parsed from `tmux list-windows`)
- Worker logs (read from `/tmp/<name>.log`)
- Click/select to view log, kill worker

### §T.5 — Wiki panel
Status: .

Quick access to memorybank:
- List pages (parsed from `memorybank/index.md`)
- Preview page content in side panel
- Jump to full page view

### §T.6 — Session tree (like Pi)
Status: .

- Store session as tree structure (JSON file)
- Each message is a node, branching possible
- `/tree` command shows visual tree
- Navigate to any node, continue from there
- Export to HTML or share

**File:** `.mix/sessions/<id>.json`

### §T.7 — Extension system
Status: .

`.agent/tui.d/` directory for user extensions:
- Python files auto-loaded by `mix-tui`
- Can register: keybindings, panels, commands, themes
- Minimal API surface: `register_keybind()`, `register_panel()`, `register_command()`

### §T.8 — Themes
Status: .

Load theme from `.agent/tui-theme.yaml`:
```yaml
colors:
  bg: "#08080f"
  fg: "#e8e8f8"
  accent: "#00ffaa"
  error: "#ff3a6e"
  muted: "#4a4a6a"
  panel_border: "#1a1a3a"
style:
  borders: rounded    # plain | rounded | thick | double
  syntax_theme: dracula
```

## File Structure (final)

```
agent/
├── mix                  # core agent (bash, ~1k lines) — minimal changes
├── mix-tui              # TUI entrypoint (Python + textual)
├── docs/
│   └── tui-plan.md      # this file
├── .agent/
│   ├── rc.sh            # agent extensions (existing)
│   ├── tui.d/           # TUI extensions (Python modules)
│   └── tui-theme.yaml   # theme config
├── .mix/
│   └── sessions/        # session tree storage
├── memorybank/          # wiki (existing)
├── index.html           # landing page (existing)
└── install.sh           # installer (existing)
```

## Dependencies

| What        | Why                  | Install                        |
|-------------|----------------------|--------------------------------|
| python3     | TUI runtime          | Already required by mix        |
| textual     | TUI framework        | `pip install textual`          |
| rich        | Markdown/syntax render | `pip install rich` (textual dep) |
| pygments    | Syntax highlighting  | `pip install pygments`         |

Graceful fallback: if `textual` not installed, `mix-tui` prints message and offers `pip install textual`, or user runs plain `mix`.

## Implementation Order

1. **§T.1** — JSON bridge in `mix` (foundation for everything)
2. **§T.2** — TUI skeleton (get something rendering)
3. **§T.3** — Keybindings (make it usable)
4. **§T.4** — Worker panel (tmux integration)
5. **§T.5** — Wiki panel (memorybank integration)
6. **§T.7** — Extension system (let users customize)
7. **§T.8** — Themes (polish)
8. **§T.6** — Session tree (advanced, optional)

## Notes for Opus 4.6

- `mix` is bash. JSON output mode must handle streaming tokens carefully — each token as a JSON chunk is expensive. Consider: buffer tokens, emit on newline or every N chars.
- textual runs its own event loop. The `mix` subprocess must be non-blocking (use `asyncio.subprocess`).
- Keep `mix-tui` as a single file initially. Split into modules only if it exceeds 1200 lines.
- The existing `mix` tmux bootstrap (`MIX_NO_TMUX=1`) — `mix-tui` should set `MIX_NO_TMUX=1` since it manages its own terminal.
- Test with: `python3 mix-tui` from project dir. It should find `./mix` automatically.
