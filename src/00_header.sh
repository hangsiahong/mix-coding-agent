
# mix — super minimal terminal coding agent
# https://ai.koompi.cloud/v1 — OpenAI-compatible
# Dependencies: bash, curl, python3

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly to keep the REPL alive

# ─── Early-exit flags (before any heavy init) ────────────────────────────────
case "${1:-}" in
  --self-test)
    # Quick health check: no network/API calls. Just verify structure.
    _st_err=""
    # python3 must exist
    command -v python3 >/dev/null 2>&1 || _st_err="${_st_err}python3 not found"$'\n'
    # curl must exist
    command -v curl >/dev/null 2>&1 || _st_err="${_st_err}curl not found"$'\n'
    # The compiled binary must have these key functions (defined later in the file,
    # but by the time this case runs they're already loaded since bash sources the
    # whole file top-to-bottom before executing — wait, no. This runs at source time.
    # So we defer the function check to after all sources are loaded.
    # For now, just check deps.
    if [ -n "$_st_err" ]; then
      echo "FAIL:$_st_err" >&2
      exit 1
    fi
    echo "OK"
    exit 0
    ;;
  --doctor)
    # Doctor mode: invoked by wrapper when current binary is broken.
    # Falls through to normal REPL init but sets flag for auto-repair.
    _DOCTOR_MODE=true
    shift
    ;;
  --version)
    echo "mix ${MIX_VERSION:-dev}"
    exit 0
    ;;
esac

