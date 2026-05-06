# Task: Fix google model prefix bleeding into default provider
Date: 2024-05-18

## Result
Switching from the Google provider to the default provider caused API calls to fail with `Model google/<model> not supported`. The Google provider sets a global `_GOOGLE_VERTEX_MODEL_PREFIX` variable which was not being unset when switching back to the default provider via `/provider default`. This caused the `google/` prefix to be erroneously prepended to models on the default koompi proxy. Added `unset _GOOGLE_VERTEX_MODEL_PREFIX` to both `/provider default` REPL handlers.

## Files Modified
- `src/25_repl_commands.sh`