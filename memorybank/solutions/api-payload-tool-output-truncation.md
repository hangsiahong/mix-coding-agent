# Tool Output Payload Truncation Guard

**Context:** Tools executing shell commands (especially `bash`, `find`, or `cat` on large files) can generate massive stdout/stderr. If passed unfiltered back to the LLM agent loop, these massive payloads trigger a `400 Bad Request` API error because they exceed the provider's max payload size or token limits, instantly terminating the session loop.

**Mechanism:**
In `src/13_tool_execution.sh` and `src/22_process_one_tool_call.sh`, all tool outputs are now intercepted before being appended to the `HISTORY` payload. 
We enforce a hard byte limit of **32KB (32,000 bytes)** per tool call.

```bash
  # Guard against massive outputs that cause API 400 Bad Request
  # Limit total response size to 32KB per turn
  local byte_len
  byte_len=$(printf '%s' "$result" | wc -c)
  if [ "$byte_len" -gt 32000 ]; then
    result="$(printf '%s' "$result" | head -c 32000)
... [TRUNCATED: Output exceeded 32KB ($byte_len bytes). If you need more, redirect to a file, pipe to 'head', or be more specific.]"
  fi
```

**Why bytes instead of tokens?**
Counting bytes via `wc -c` is computationally trivial and requires no python overhead or dependency. Assuming ~3.5 chars/bytes per token, 32KB is roughly 9,000 tokens — well within the context limits of all modern models, but safely away from massive 500k+ byte payloads that cause immediate API rejection.

**Related Systems:**
This operates *after* `smart-bash-truncation.md` logic (which extracts errors). If the smart truncation fails or if a non-bash tool dumps huge data, this payload byte guard acts as the absolute last line of defense before the API call is made.