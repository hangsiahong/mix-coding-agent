# 🛠️ mix-skill: Extending and Hacking Mix

## 1. What is Mix?
`mix` is a single-file Bash/Python hybrid terminal agent built with ruthlessly minimal dependencies.
- The `mix` binary you run is compiled. NEVER manually edit `mix` itself!
- To make changes, edit the source files inside `src/*.sh`.
- Rebuild via `bash ./build.sh && cp mix.compiled mix`.

## 2. Architecture & File Locations
| File | Purpose |
|------|---------|
| `01_config.sh` | Main global configurations (`ACTIVE_SKILLS`, `STREAM`, etc). |
| `03_system_prompt_*.sh` | Contains the `build_system_prompt` function (injection target for rules/skills). |
| `10_tools_openai_function_calling.sh` | The JSON definitions for the tools the LLM sees. |
| `13_tool_execution.sh` | The actual bash logic handling the function calls invoked by the LLM. |
| `14_risk_scoring_*.sh` | The security scanner (`score_risk`). Check this if terminal commands falsely get blocked. |
| `18_streaming_api_call.sh` | Handles HTTP/2 live streaming via Python `urllib` (no curl). |
| `24_agent_loop_*.sh` | The main LLM execution pipeline (call API -> parse response -> execute tools). |
| `25_repl_commands.sh` | Where slash commands (`/skill`, `/yolo`, `/subagent`) are mapped. |
| `27_main_repl.sh` | The active `read -e` loop that captures user input across the prompt. |

## 3. How to extend Mix safely
If a user wants to build an "extensible feature" for `mix`, you should:
1. Locate the correct target script in `src/*.sh`.
2. Add your logic or tool inside `src/*.sh`.
3. If it's a new tool, define the JSON schema in `src/10_*` and implement the case in `src/13_*`.
4. If it's a new `/` command, add it to `src/25_repl_commands.sh` and update `/help`.
5. Finally, ALWAYS recompile: `bash ./build.sh && cp mix.compiled mix`.

## 4. Skills Ecosystem
Skills are raw Markdown files located in `~/.mix/skills/` or `.mix/skills/`.
They get injected globally into the context window via the `/skill <name>` REPL command. If the user asks for a new skill, just create `<concept>.md` in `~/.mix/skills/`!