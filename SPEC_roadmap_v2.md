# SPEC: Roadmap V2 — Agent Capabilities expansion

## 1. Multi-file Creation (`create_files`)
- **Goal:** Allow creating multiple files in one turn without sequential tool call overhead.
- **Interface:** `create_files(files: {path: content})`
- **Cache:** All created files must be added to `_FILE_CACHE` immediately.

## 2. File Move/Delete (`move_file`, `delete_file`)
- **Goal:** First-class support for refactoring.
- **Cache Sync:** `move_file` should update the path in `_FILE_CACHE`. `delete_file` should remove it.
- **Safety:** Prevent accidental deletion of root or critical agent files.

## 3. Background Jobs (`/jobs`, `check_job`)
- **Goal:** Run long-running commands (tests, installs) without blocking the REPL.
- **Implementation:** Use `tmux` split/windows or background processes.
- **Interface:** `bash` gets an optional `background: true` flag. Returns `job_id`.

## 4. Definition-aware Search (`find_definition`)
- **Goal:** Skip the noise of `grep` and find where a class/function is defined.
- **Implementation:** Leverage `ctags` indices if available.

## 5. Interactive "Fixit" Mode (`/doctor`)
- **Goal:** Deep diagnostic tool for environment issues.
- **Process:** snapshot `env`, `df -h`, `free -m`, `tail logs`, then ask a "diagnostic-specialist" LLM for a fix.

## 6. Formalized Message Bus (`.mix/bus/`)
- **Goal:** Reliable multi-agent coordination.
- **Interface:** `send_message(to, msg)`, `read_messages()`.
- **Implementation:** Structured JSON files in `.mix/bus/` with file-locking.
