# Tool System Enhancements

## Architecture
The tool system in `mix` now uses a multi-layered execution model with real-time TUI feedback.

### Execution Flow
1. **Request**: LLM sends JSON tool call.
2. **Signal**: `run_tool` prints a themed status line (e.g., `📖 read: path/to/file`).
3. **Execution**: Logic handles the specific tool (Python for complex logic, Bash for simple commands).
4. **Resilience**: `edit_file` uses 4 strategies to avoid "old_text not found" errors.

### Visual Feedback
| Tool | Icon | Color | Description |
| :--- | :--- | :--- | :--- |
| `bash` | ⊚ | Green | Shell command execution |
| `read_file` | 📖 | Blue | Reading file contents |
| `edit_file` | 📝 | Yellow | Multi-strategy search/replace |
| `create_file` | ➕ | Green | New file creation |
| `list_files` | 📂 | Cyan | Directory listing |
| `search_files` | 🔍 | Magenta | Regex grep search |

## Recent Fixes
- **Empty Compact Summary**: Fixed by moving summarization instruction to the *end* of the message list (User role).
- **Copilot 400**: Resolved by injecting `Editor-Version` and `Editor-Plugin-Version` headers required by GitHub's proxy.
