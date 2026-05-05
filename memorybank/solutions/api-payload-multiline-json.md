# API Payload Builder JSON Multiline Desync

## Issue
Users reported an `API error 'payload'` and a python `KeyboardInterrupt` crash loop when extensions (specifically `fetcher`) were loaded.

## Root Cause Analysis
1. The `mix` API calling scripts (`src/16_api.sh`, `src/18_streaming_api_call.sh`) pass JSON payloads to python via a `printf` pipeline:
   ```bash
   printf '%s\n%s\n%s\n%s\n%s\n' \
     "$SYS_PROMPT_ENCODED" \
     "$TOOLS_JSON" \
     "$_hist_for_api" \
     "$_model" \
     "$_extra_payload" | python3 -c '...'
   ```
2. The python script decodes these using positional readlines:
   ```python
   s=json.loads(sys.stdin.readline())
   t=json.loads(sys.stdin.readline())
   ```
3. `TOOLS_JSON` was originally a hardcoded, single-line JSON string.
4. When an extension (e.g. `fetcher`) with a multiline JSON tool schema was loaded, `_ext_rebuild_tools` injected it verbatim.
5. The `TOOLS_JSON` became multiline. `sys.stdin.readline()` only read the first line (`[{` or `{`), corrupted the JSON array parsing, and shifted the subsequent readlines out of phase.
6. The python parser crashed, resulting in `FAIL:payload`, which the API correctly rejected with 400 Bad Request `API error 'payload'`.

## Fix
In `src/04b_extension_rebuild_tools.sh`, extension schemas are now intercepted and minified into single-line JSON strings before being concatenated:
```bash
_schema=$(${_ext}_tool_schema 2>/dev/null | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)))' 2>/dev/null)
```
This forces single-line structure AND serves as a strict JSON validation pass, preventing a malformed extension from bricking the entire tool array.
