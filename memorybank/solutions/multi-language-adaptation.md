# Multi-Language Adaptation

`mix` is explicitly designed as a multi-language agent capable of operating on advanced production codebases like Next.js (TypeScript), Rust, and Python. It achieves this via two primary mechanisms:

### 1. AST-Aware Code Context
Instead of relying purely on rudimentary regex to read the project structure, `mix` automatically checks for `Universal Ctags`. If present, it natively parses the Abstract Syntax Trees (AST) of the files in the repository.
- **Python:** Understands Classes, Methods, Variables.
- **Rust:** Understands Structs, Enums, Traits, and Impls.
- **TypeScript/React:** Understands Interfaces, Types, Components, and exported functions.
This condensed map is injected into the prompt, giving the LLM immediate architectural awareness without needing to `search_files` or `read_file` blindly.

### 2. Auto-Verification Engine (`src/13a_auto_verify.sh`)
When the agent executes an `edit_file` or `create_file` tool call, `mix` intercepts the action and dynamically assesses the file extension to run the appropriate local linters and typecheckers *before* confirming the edit to the LLM:
- **`.js` / `.ts` / `.tsx` (Node.js/Next.js):** Checks for `node_modules/.bin/eslint` and `node_modules/.bin/tsc`. Runs them on the targeted file (`tsc --noEmit`).
- **`.rs` (Rust):** Executes `cargo check` (with an extended 30-second timeout due to compilation overhead).
- **`.py` (Python):** Automatically compiles syntax via native `python3 -m py_compile`, runs `ruff` (if installed), and invokes `mypy` if `pyproject.toml` or `mypy.ini` is found.
- **`.sh` / `.bash`:** Triggers `shellcheck` and `bash -n`.

If any check fails, the error trace is aggressively injected into the tool execution result via `[VERIFY: FAILED]`. This forces the LLM to self-heal and fix the syntax error/typing bug *immediately* in the next turn, drastically reducing broken code commits.
