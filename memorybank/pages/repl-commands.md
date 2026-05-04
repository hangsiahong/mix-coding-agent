# REPL Commands Reference

## Cavekit (spec-driven development)

| Command | Description |
|---|---|
| `/spec <idea>` | Create SPEC.md with §G §C §I §V §T §B |
| `/spec bug: <desc>` | Backprop bug → §B entry + §V invariant |
| `/spec amend <section>` | Amend existing spec section |
| `/spec from-code` | Distill SPEC.md from existing codebase |
| `/build [§T.n\|--next\|--all]` | Execute §T tasks, flip status . → ~ → x, commit each |
| `/check [§V\|§I\|§T\|--all]` | Drift report — reads only, zero writes |

## Agent

| Command | Description |
|---|---|
| `/flush` | Clear history completely |
| `/compact` | Force compact history now |
| `/model [id]` | Show or switch model (validates against provider) |
| `/models` | List available models for current provider |
| `/provider [name]` | Show/switch provider. Actions: login, models, default |
| `/history` | Show message count in history |
| `/caveman [off\|lite\|full\|ultra]` | Toggle response compression |
| `/mode [fast\|deep\|plan]` | Switch agent reasoning mode |
| `/yolo` | Toggle auto-confirm (MED-risk auto-runs) |
| `/undo` | `git reset --soft HEAD~1` (requires git) |

## Workers & Subagents

| Command | Description |
|---|---|
| `/workers` | List tmux windows |
| `/worker <name> <cmd>` | Spawn bash worker in tmux window |
| `/subagent <name> <task>` | Spawn full mix instance as tmux worker |
| `/skill <name>` | Load a skill markdown into system prompt |
| `/skills` | List active skills |
| `/skill clear` | Clear all active skills |

## AFK Mode

| Command | Description |
|---|---|
| `/afk` | Analyse codebase, generate plan (default: TODO/FIXME/git/audit) |
| `/afk <prompt>` | Custom task — plan around your specific prompt instead of default analysis |
| `/afk setup` | Configure Telegram bot for remote approval |
| `/afk apply` | Apply saved plan from `~/.mix/afk-plan.md` |
| `/afk log` | Show saved plan |
| `/afk stop` | Kill AFK worker tmux window |

## Clipboard & Input

| Command | Description |
|---|---|
| `/paste` | Paste clipboard as context |
| Ctrl+V | Paste media (image or text) from system clipboard |
| Ctrl+E | Open vim to edit current input line |
| @ | Tab-complete file references (@path/to/file) |
| / | Tab-complete slash commands |

## REPL Features

- **Bracketed paste**: multi-line paste collapsed to `[paste N lines]` token
- **Piped mode**: `echo "task" | mix` — auto-confirms everything, exits after one task
- **Tab completion**: slash commands, skill names, file paths with @ prefix
- **SIGINT**: Ctrl+C cancels current turn, returns to prompt (doesn't exit)
- **EXIT trap**: cleans up spinners + /tmp/mix-* files on crash or exit
