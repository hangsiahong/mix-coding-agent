# Prompt Optimization Audit (2026-07-15)

## Current System Prompt Budget

**Total: ~7,084 tokens / ~21,252 chars** (measured live on this repo)

| Section | Chars | ~Tokens | % of Total | Type |
|---------|-------|---------|------------|------|
| Global memory | 6,810 | 2,270 | 32% | 🔴 highest |
| SPEC.md | 5,057 | 1,685 | 24% | 🟡 |
| Repo map | 4,796 | 1,598 | 23% | 🟢 useful |
| Task rules | 1,086 | 362 | 5% | 🟢 core |
| Wiki pattern | 1,834 | 611 | 9% | 🟡 |
| Workers/Skills | 576 | 192 | 3% | 🟢 small |
| Caveman mode + misc | ~893 | ~298 | 4% | 🟢 small |

## Is 26k Prompt / 13k Context Bad?

**Not terrible, but worth trimming.** Here's why:

- 26k total prompt = ~7k system + ~13k history + ~6k tool output/turn
- For 128k context (glm-5): 26k = 20% used → **plenty of room**
- For 32k context models: 26k = 81% → **dangerous, early compact**
- For 8k context models: **impossible, instant overflow**

The system prompt at ~7k tokens is the "tax per turn" — it doesn't compress. History at 13k is manageable (compact triggers at 60 msgs).

## Recommendations (Priority Order)

### 1. 🔴 Global Memory — Biggest Offender (2,270 tokens / 32%)

**Current:** Entire `~/.mix/memory.md` injected verbatim every call.

This file has grown to 6,810 chars with detailed bug fixes, architecture notes, and historical debugging sessions. Much of it is stale (e.g., sandbox audit findings from months ago).

**Fixes:**
- **Cap at 2,000 chars** (from current 6,810). Keep last N entries, auto-trim old ones.
- **Skip lines older than 30 days** (parse date headers if present, else keep last 20 bullets).
- **Code change:** In `build_system_prompt()`, after reading `_gmem_content`, truncate to budget:
  ```bash
  _GMEM_BUDGET=2000
  if [ ${#_gmem_content} -gt "$_GMEM_BUDGET" ]; then
    _gmem_content=$(printf '%s' "$_gmem_content" | tail -c "$_GMEM_BUDGET")
  fi
  ```
- **Savings: ~1,500 tokens**

### 2. 🟡 SPEC.md — 1,685 tokens / 24%

**Current:** First 200 lines injected every call.

SPEC.md has 3 completed specs. Only the active one matters.

**Fixes:**
- **Only inject when actively building** (detect `/spec` or `/build` in recent history).
- **Or cap at 1,000 chars** — just the active spec's goal + task status.
- **Savings: ~1,000 tokens**

### 3. 🟡 Wiki Pattern — 611 tokens / 9%

**Current:** Full wiki instructions injected every call, even when no memorybank exists.

**Fixes:**
- **Only inject when `memorybank/` directory exists.** Already says "use when memorybank/ exists" but the text is always present.
- **Savings: ~611 tokens** (on projects without memorybank)

### 4. 🟢 Repo Map — 1,598 tokens / 23%

Already well-budgeted at 4,800 char hard cap. This is the highest-value section — keep as-is.

### 5. 🟢 Task Rules — 362 tokens / 5%

Core behavior. Don't touch.

## Potential Savings Summary

| Optimization | Tokens Saved | Risk |
|-------------|-------------|------|
| Cap global memory at 2k chars | ~1,500 | Low — old entries less relevant |
| SPEC.md: cap or conditional | ~1,000 | Low — only needed during /spec /build |
| Wiki pattern: conditional | ~611 | None — skip when no memorybank |
| **Total** | **~3,111** | |

**After optimization: ~3,973 tokens system prompt** (down from ~7,084)

## What About History (13k)?

History compaction already works well (triggers at 60 msgs, keeps last 10 verbatim). The 13k is reasonable for a multi-turn session. No changes needed.

## Comparison with Other Agents

| Agent | System Prompt | Notes |
|-------|-------------|-------|
| Claude Code | ~8-12k tokens | Heavy tool definitions |
| Aider | ~3-5k tokens | Minimal, repo-map focused |
| Cursor | ~5-8k tokens | Model-dependent |
| **Mix (current)** | **~7k tokens** | **Balanced, room to trim** |
| **Mix (optimized)** | **~4k tokens** | **Competitive with Aider** |

## Verdict

Not bloated — but global memory grew unbounded and SPEC.md is always-on. Two easy fixes cut system prompt by 44% without losing capability. The agent is solid; just needs a diet on the two growing sections.
