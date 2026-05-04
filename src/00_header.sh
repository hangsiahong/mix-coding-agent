
# mix — super minimal terminal coding agent
# https://ai.koompi.cloud/v1 — OpenAI-compatible
# Dependencies: bash, curl, python3

set -uo pipefail
# NOTE: no `set -e` — we handle errors explicitly to keep the REPL alive

# ─── Early-exit flags (before any heavy init) ────────────────────────────────
case "${1:-}" in
  --self-test)
    # Quick health check: syntax + basic structure, no network/API calls
    _st_err=""
    # Verify all sourced files parse correctly
    for _st_f in "${BASH_SOURCE[0]}"; do
      _st_out=$(bash -n "$_st_f" 2>&1) || _st_err="$_st_err$_st_out"$'\n'
    done
    # Verify python3 available
    command -v python3 >/dev/null 2>&1 || _st_err="${_st_err}python3 not found"$'\n'
    # Verify basic functions exist (we're in the compiled binary, so they should)
    if ! type _load_provider >/dev/null 2>&1; then
      _st_err="${_st_err}_load_provider function missing"$'\n'
    fi
    if [ -n "$_st_err" ]; then
      echo "FAIL:$_st_err" >&2
      exit 1
    fi
    echo "OK"
    exit 0
    ;;
  --doctor)
    # Doctor mode: invoked by wrapper when current binary is broken
    # Falls through to normal init but sets a flag for auto-repair
    _DOCTOR_MODE=true
    shift
    ;;
  --version)
    # Print version info
    _V_MIX_VER="${MIX_VERSION:-dev}"
    echo "mix $_V_MIX_VER"
    exit 0
    ;;
esac

