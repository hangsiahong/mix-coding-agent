# Extension System

## Overview
Drop-in plugin system. Put `.sh` in `~/.mix/extensions/` or `.mix/extensions/` — convention-based hooks customize the harness without forking.

## Source
`src/04b_extension_system.sh` — 245 lines

## How It Works

### Directories
- **Global**: `~/.mix/extensions/<name>.sh` — available everywhere
- **Project**: `.mix/extensions/<name>.sh` — project-local, overrides global (same name wins)

### Convention Hooks
Each extension defines functions following `<name>_<hook>` pattern:

| Hook | Called When | Return |
|---|---|---|
| `<name>_init` | On load | — |
| `<name>_cmd` | REPL input, before built-in commands | 0 = handled, 1 = pass through |
| `<name>_tool` | Tool dispatch, before "unknown" fallback | prints result, or return 1 |
| `<name>_on_edit` | After successful edit_file | — |
| `<name>_on_create` | After successful create_file | — |
| `<name>_on_bash` | After successful bash execution | — |
| `<name>_on_session` | On session save/load | — |
| `<name>_on_shutdown` | EXIT trap | — |

### REPL Commands
- `/ext load <name>` — load an extension
- `/ext unload <name>` — unload an extension
- `/ext create <name>` — scaffold template with all hooks documented
- `/ext reload` — reload all extensions
- `/ext list` — show loaded extensions

### Dispatch Priority
1. Extensions get **first crack** at REPL commands (before built-in handlers)
2. Extension tools dispatched before "unknown tool" fallback in `process_tc()`
3. Project extensions override global extensions (same name)

### Integration Points
- `src/25_repl_commands.sh` — command dispatch + `/ext` commands
- `src/22_process_one_tool_call.sh` — tool dispatch + lifecycle hooks (on_edit, on_create, on_bash)
- `src/27_main_repl.sh` — shutdown hook + tab-completion for extension names
- `build.sh` — load order: `04_project_local_extensions → 04b_extension_system → 05_pre_edit_diff_preview`

### Auto-Load
Extensions auto-load on startup. `_ext_load_all()` scans both directories, deduplicates (project wins), sources each file.

### Example Extension
```bash
# ~/.mix/extensions/auto-lint.sh

auto_lint_init() {
    echo "Auto-linter loaded"
}

auto_lint_on_edit() {
    local file="$1"
    case "$file" in
        *.sh) shellcheck "$file" 2>&1 || true ;;
        *.py) python3 -m py_compile "$file" 2>&1 || true ;;
    esac
}
```

## Philosophy
Like pi.dev: "Change the harness, not your workflow." Drop a `.sh` file, load it, keep going.

## Tests
24/24 in `tests/extensions.bats`
