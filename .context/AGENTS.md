# AGENTS.md — mix agent instructions

Schema for memorybank/ structure and conventions.
Co-evolve this file as the project grows.

## memorybank conventions

- one concept per file, slug filename (kebab-case)
- every new page → update memorybank/index.md
- every session task → append to memorybank/log.md
- solutions: cause / fix / command / date (see solutions/.keep for format)
- sources: one file per external source ingested

## response style

caveman full by default:
- drop articles, filler, hedging
- fragments OK
- pattern: [thing] [action] [reason]. [next step].
- exception: full sentences for security warnings, irreversible ops

## tool use rules

- bash before read_file when possible (faster for quick checks)
- edit_file old_text: must be unique in the target file — use enough context
- list_files before edit_file on new projects (understand structure first)
- git push: always HIGH risk — require explicit YES

## when to write to memorybank

- error solved that took >1 attempt → solutions/
- external source read → sources/
- new concept discovered → concepts/
- all above → update index.md + append log.md
