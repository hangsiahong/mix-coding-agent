# Solution: Roadmap V2 — Agent Capabilities Expansion

Implemented 6 major features to enhance the agent's autonomy and multi-agent coordination.

## 1. Multi-file Creation (`create_files`)
- **Impact:** Reduced turn count for boilerplate/refactoring.
- **Cache:** Automatically injects all new files into the `_FILE_CACHE`.

## 2. Refactoring Support (`move_file`, `delete_file`)
- **Impact:** Allows first-class file management beyond `bash` commands.
- **Cache Sync:** `move_file` preserves cache content while updating the path; `delete_file` purges the cache entry to prevent stale references.

## 3. Background Jobs
- **Interface:** `bash` tool now accepts `background: boolean`.
- **Status:** New `check_job(job_id)` tool allows polling the last 100 lines of job logs.
- **Benefit:** Prevents blocking the REPL for long tasks like `npm install` or massive test suites.

## 4. Definition Search (`find_definition`)
- **Engine:** Uses `ctags` (with regex fallback).
- **Benefit:** Agent can jump directly to code definitions instead of sifting through `grep` noise.

## 5. REPL Diagnostics (`/doctor`)
- **Mechanism:** Snapshots system info (disk, memory, env, failures) and feeds it to a "Senior SRE" specialized prompt.
- **Benefit:** Provides deep insight into environmental failures (e.g., full disk, missing env vars).

## 6. Formalized Message Bus
- **Interface:** `send_message(to, message)` and `read_messages()`.
- **Backend:** Uses `.jsonl` files in `${WORKDIR}/.mix/bus/` for persistent, file-based messaging.
- **Benefit:** Enables structured coordination between the main agent and parallel subagents.
