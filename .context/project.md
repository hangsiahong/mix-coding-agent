# mix — project context

## what this is

mix is a single-file terminal coding agent (`mix`).
Talks to OpenAI-compatible APIs. Zero install. Pure bash.

## stack

- runtime: bash + python3 + curl
- api: OpenAI-compatible `/chat/completions`
- default model: glm-5 (KConsole AI gateway)
- tools: bash, read_file, edit_file, list_files (function-calling format)

## key design decisions

- single file: no install, portable, auditable
- yolo mode on by default: auto-confirm LOW/MED risk commands
- git-safe: every edit goes through diff → confirm → staged commit → rollback-on-decline
- risk scoring before every bash command: BLOCKED / HIGH / MED / LOW
- self-healing: sudo retry on EACCES, npx retry on command not found
- memorybank/: compounding knowledge base, auto-maintained across sessions
- caveman style: compressed, direct responses — no fluff

## conventions

- absolute paths for all file operations
- edit_file old_text must be unique in the file
- bash failures tagged [FAILED exit=N]
- history stored in .agent_history.json (gitignored)

## structure

```
mix                  main script
README.md            user docs
memorybank/          LLM-maintained knowledge base
  index.md           content catalog
  log.md             append-only task log
  solutions/         per-problem fix pages
  sources/           ingested source summaries
.context/            project context for LLMs
.agent/rc.sh         project-local overrides
```
