# Codebase Audit — mix coding agent (2025-05)

Comprehensive audit of 1520 lines across 28 source files. Covers security, correctness, robustness, architecture, and DX.

---

## 1. SECURITY

### 🔴 Critical

**S1. `eval "$cmd"` — arbitrary code execution (08_self_healing, 13_tool_execution)**
- `run_with_heal()` passes LLM-extracted command through `eval "$cmd"` — any shell metacharacters `$(...)`, backticks, `; rm -rf /` all expand.
- `run_tool bash` in 13 does the same.
- The risk scorer (14) is a regex filter applied *before* eval, which is the only guard. A single regex bypass = full system compromise.
- **Fix**: Replace `eval "$cmd"` with `bash -c "$cmd"` or `eval` with proper quoting. Better: use `bash -c` + pass cmd via env/var to avoid double-expansion.

**S2. API key logged to `.agent_history.json` in cleartext**
- If the LLM ever echoes back the API key (or user pastes it), it lands in `HIST_FILE` on disk unencrypted.
- **Fix**: Redact API keys from tool results before saving to history.

**S3. `sudo bash -c "$cmd"` without sanitization (08_self_healing)**
- If permission-denied detected, prompts for sudo and re-runs the *exact same command* as root. If the command contained exploits masked by the permission error, root is compromised.
- **Fix**: Show the full command before sudo prompt. Never auto-sudo multi-pipe commands.

**S4. `source "$WORKDIR/.agent/rc.sh"` and `source "$HOME/.mix/rc.sh"` (04)**
- Arbitrary code execution on startup. A malicious repo with `.agent/rc.sh` = instant compromise.
- **Fix**: Display warning when sourcing, or require explicit opt-in.

### 🟡 Medium

**S5. Fork-bomb detection only checks `:(){:|:&};:` literally (14)**
- Trivially bypassed with whitespace, variable indirection, base64 decode, etc.
- **Fix**: This is inherently unfixable with regex. Document that risk scoring is best-effort, not a sandbox.

**S6. Heredoc body strip is fragile (14)**
- `head -n1` strips heredoc content for risk scanning. Multi-line commands before the heredoc (e.g., `cmd1 && cat <<'EOF'\nrm -rf /\nEOF`) lose the dangerous part.
- **Fix**: Parse heredoc properly or scan full command.

**S7. No rate limiting on API calls**
- Agent loop can fire unbounded API calls (MAX_TURNS=50). A runaway LLM = API bill spike.
- **Fix**: Add per-session token/cost estimator. Warn at thresholds.

**S8. `urllib` streaming uses no TLS cert verification override (18)**
- Default `urllib.request.urlopen` validates certs, which is fine. But `timeout=1800` (30 min) is very long — connection could be hijacked.
- **Fix**: Reduce timeout. Consider short reads.

**S9. Skills loaded via `cat "$_skill"` in system prompt (03)**
- If skill file is large or malformed, it inflates context window and could inject prompt attacks.
- **Fix**: Truncate skill files. Validate markdown format.

---

## 2. CORRECTNESS BUGS

**B1. `edit_file` early return skips result output (13)**
```bash
edit_file)
      ...
      result=$(python3 -c "..." "$path" "$old_text" "$new_text")
      return   # ← returns before printing $result
      ;;
```
- `return` exits `run_tool()` before the `[ -z "$result" ]` fallback at bottom. The caller in `22_process_one_tool_call.sh` calls `run_tool edit_file` and captures output — but `run_tool` never `printf`'s the result. This means edit errors from `run_tool` are silently lost.
- Note: `22_process_one_tool_call.sh` calls `run_tool edit_file` and uses the result, so this may work because the caller doesn't rely on stdout — but the function is inconsistent with other tools.

**B2. `append_raw` uses string manipulation on JSON array (12)**
```bash
HISTORY="${HISTORY%]},$msg]"
```
- This strips trailing `]`, appends `,msg]`. If `$HISTORY` contains `]` inside a JSON string value, it corrupts the JSON.
- **Fix**: Use python3 for append like `append_text` does, or ensure JSON strings never contain `]`.

**B3. `compact_history` uses `curl` instead of the project's urllib streaming (12)**
- Non-streaming compact call uses `curl` while streaming uses `urllib`. Inconsistent. If `curl` is unavailable or behaves differently, compact silently fails.
- **Fix**: Extract API call helper shared between compact and main.

**B4. `search_files` hardcodes file extensions (13)**
```bash
--include='*.sh' --include='*.js' --include='*.ts' ...
```
- Missing: `.c`, `.cpp`, `.h`, `.java`, `.rb`, `.php`, `.lua`, `.zig`, `.nix`, `.tf`, `.dockerfile`, `.env`, `.conf`, `.ini`, `.cfg`.
- **Fix**: Remove `--include` flags entirely (grep all files) or make configurable.

**B5. Context window estimator divides by 4 (20)**
```bash
local est_tokens=$(( hist_chars / 4 ))
```
- JSON history has overhead (keys, quotes, escaped chars). Real ratio is ~3-3.5 chars/token for code-heavy content. Bar will undercount.
- **Fix**: Use 3.0 or apply a JSON overhead factor.

**B6. Plan mode appends extra user message without adding to history (23)**
```python
msg.append({"role":"user","content":"List your plan..."})
```
- The planning call injects a user message that never gets added to `$HISTORY`. If the model references this message later, context is inconsistent.

**B7. `FAIL_STREAK` reset on user-declined commands (22)**
```bash
else result="User declined (HIGH risk)."; FAIL_STREAK=0; fi
```
- User declining a HIGH risk command resets the failure streak. If the LLM tried 3 failing commands, then tries a dangerous one the user declines, the streak resets — losing the recovery hint signal.
- **Fix**: Only reset FAIL_STREAK on actual success, not on user decline.

---

## 3. ROBUSTNESS

**R1. No trap for SIGTERM/SIGHUP — orphan spinner processes**
- If mix is killed (not Ctrl+C), `_SPIN_PID` background process becomes orphan, spinning forever.
- **Fix**: `trap 'stop_spinner; exit' SIGTERM SIGHUP EXIT`

**R2. Temp files not cleaned on crash (13, 16, 18, 22, 23)**
- `mktemp` files in multiple locations. If script crashes, they leak in `/tmp`.
- **Fix**: `trap 'rm -f /tmp/mix-*' EXIT` or use `mktemp -u` patterns with cleanup.

**R3. `python3 -c` invocations silently fail everywhere**
- Almost every python3 one-liner ends with `2>/dev/null || true`. If python3 crashes or has import errors, the failure is swallowed.
- **Fix**: At minimum, log failures. Add a startup python3 health check.

**R4. `HISTORY` as shell variable — size limits**
- Bash strings have no hard limit but passing 100KB+ JSON through shell variables + pipes to python3 is fragile. `printf '%s' "$HISTORY"` with large payloads can hit ARG_MAX.
- **Fix**: Use temp files for history once it exceeds a threshold.

**R5. `read -e` depends on GNU readline (27)**
- `read -e` enables readline editing but isn't POSIX. Fails on FreeBSD/macOS with non-bash shells.
- Already using `#!/usr/bin/env bash` so this is OK, but tab completion binding `bind -x` is bash-specific. Fine for stated deps.

**R6. Tmux bootstrap `exec` replaces process (02)**
- If tmux session already exists, `exec tmux attach` replaces the shell. The original process args `"$@"` are passed but never used in the new-session branch.
- **Fix**: Pass `"$@"` to `tmux new-session` as well.

**R7. `run_with_heal` retry with npx (08)**
```bash
out=$(eval "npx $cmd" 2>&1)
```
- If `$cmd` is `rm -rf something`, this becomes `npx rm -rf something` which npx might interpret differently or prompt for install.
- **Fix**: Only retry with npx/node_modules for known safe commands.

---

## 4. ARCHITECTURE

**A1. Duplicate tool execution paths**
- `run_tool` in `13_tool_execution.sh` and `process_tc` in `22_process_one_tool_call.sh` both implement tool dispatch.
- `22` calls `run_tool` for some tools but reimplements bash risk-scoring and execution inline. Two places to update when adding tools.
- **Fix**: `process_tc` should always delegate to `run_tool`. Move risk scoring + confirmation into `run_tool` or a wrapper.

**A2. JSON construction via string concatenation**
- `append_raw` does `HISTORY="${HISTORY%]},$msg]"` — hand-rolling JSON. Fragile, hard to debug.
- `TOOLS_JSON` is a single-quoted bash string containing hand-crafted JSON.
- **Fix**: Generate TOOLS_JSON with python3. Use python3 for all JSON mutations.

**A3. No dependency injection for API**
- `BASE_URL`, `API_KEY`, `MODEL` are globals. Functions reach into them directly.
- **Fix**: Pass as arguments or use a config object. Low priority for bash.

**A4. System prompt includes full skill file contents inline (03)**
```bash
base+="\n--- $_skill ---\n$(cat "$_skill" 2>/dev/null)"
```
- Multiple large skills = bloated system prompt = fewer turns before context exhaustion.
- **Fix**: Summarize skills or truncate.

**A5. SPEC.md capped at 200 lines (03)**
```bash
_spec_content=$(head -200 "$WORKDIR/SPEC.md" 2>/dev/null)
```
- Large specs get silently truncated. No warning.
- **Fix**: Show truncation notice or use dynamic sizing based on context window.

**A6. No unit tests**
- Zero test coverage. All testing is manual.
- **Fix**: At minimum, test `score_risk`, `parse_resp`, `run_tool`, `append_raw` with known inputs.

---

## 5. UX / DX

**U1. `/yolo` toggle message is confusing**
```
Yolo mode ON  — auto-confirming commands (guardrails active).
```
- "Yolo" implies no guardrails, but message says guardrails are active. Contradictory.
- **Fix**: Rename to "auto-confirm" or clarify: "Auto-confirm MED-risk commands. HIGH/BLOCKED still gated."

**U2. No `/undo` command**
- Git auto-commits are great, but there's no `/undo` to revert the last commit.
- **Fix**: Add `/undo` = `git reset --soft HEAD~1`.

**U3. Error messages are terse**
- `FAIL:payload`, `FAIL:parse`, `FAIL:stream` — no context.
- **Fix**: Include curl error code or python exception message.

**U4. No progress indicator during compact_history**
- Shows `\r↻ compacting history (N msgs)...` but no spinner. Long compaction looks frozen.
- **Fix**: Use `start_spinner "compacting"`.

**U5. Piped mode exits after one task**
- `read -r INPUT || break` then `[ "$INTERACTIVE" = false ] && break` — can't pipe multiple tasks.
- **Fix**: Loop until stdin EOF instead of breaking after first.

**U6. Autocomplete @-files searches entire project every TAB**
```bash
done < <(find . -type d \( -name ".git" -o ... \) -prune -o -type f -print 2>/dev/null | ...)
```
- In large projects, this is slow (~100ms+ per tab press).
- **Fix**: Cache file list. Or limit depth. Or use `fd` if available.

---

## 6. CODE QUALITY

**Q1. Variable naming inconsistency**
- Mix of `snake_case` (`_tools_used`), `UPPER` globals (`HISTORY`), and `camelCase` (`base`).
- **Fix**: Pick one convention. Bash convention: UPPER for globals, lower for locals, underscore prefix for private.

**Q2. Comments are sparse**
- Complex python3 one-liners have zero comments. Risk scoring regex has no examples.
- **Fix**: Add regex examples in comments. Document python3 inline scripts.

**Q3. Dead code in `run_tool bash` (13)**
- `run_tool bash` does raw `eval "$cmd"` without risk scoring. But `process_tc bash` (22) does risk scoring and calls `run_with_heal` instead. `run_tool bash` is dead code — never called for bash commands.
- **Fix**: Remove bash case from `run_tool` or note it's unused.

**Q4. `index.html` line count claim is stale**
```
<div class="grid-val">1368</div>
```
- Actual line count is 1520 (or 1721 including install.sh/build.sh).
- **Fix**: Make dynamic or update.

---

## 7. PERFORMANCE

**P1. `python3 -c` fork per tool call**
- Every JSON parse spawns a python3 process. For a multi-tool turn (edit + bash + search), that's 6-8 python3 forks.
- **Fix**: Use a persistent python3 coprocess (FIFO/named pipe) or switch to jq for simple JSON ops.

**P2. `build_system_prompt` runs `cat` on every skill file per API call**
- System prompt rebuilt every turn. Skills re-read from disk every time.
- **Fix**: Cache skill contents. Only rebuild on skill change.

---

## Summary Table

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Security | 4        | 0    | 5      | 0   |
| Bugs     | 2        | 2    | 3      | 0   |
| Robustness | 1      | 2    | 4      | 0   |
| Architecture | 0    | 2    | 4      | 0   |
| UX       | 0        | 1    | 4      | 1   |
| Quality  | 0        | 0    | 3      | 1   |
| Performance | 0     | 1    | 1      | 0   |

### Top 5 priorities (fix first)
1. **S1**: Replace `eval "$cmd"` with safer execution
2. **B1**: Fix `edit_file` early return in `run_tool`
3. **R1**: Add trap for orphan spinner cleanup
4. **A1**: Deduplicate tool execution paths
5. **B2**: Fix `append_raw` JSON string manipulation

### Overall assessment
Impressive 1520-line agent with streaming, git integration, risk scoring, and a wiki system. The main risks are: (1) shell `eval` as the execution model — fundamentally hard to secure with regex filtering, (2) hand-rolled JSON in bash — fragile at scale, (3) zero tests — refactoring is dangerous. The architecture is clean for bash — well-split files, clear naming. Low-hanging fruit: fix B1 (real bug), add EXIT trap, remove dead code.
