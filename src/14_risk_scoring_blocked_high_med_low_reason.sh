# ─── Risk Scoring: BLOCKED | HIGH | MED | LOW <reason> ──────────────────────
# Usage: read -r _risk _reason <<< "$(score_risk "$cmd")"
score_risk() {
  local c="$1"
  # Scan full command for blocked patterns, but use head for generic write detection
  local c_head
  c_head="$(printf '%s' "$c" | head -n1)"

  # ── BLOCKED ─────────────────────────────────────────────────────
  printf '%s' "$c" | grep -qF ':(){:|:&};:' \
    && echo "BLOCKED fork-bomb" && return
  printf '%s' "$c" | grep -qE 'dd .+of=/dev/[hs]d|mkfs\.' \
    && echo "BLOCKED disk-wipe" && return
  if printf '%s' "$c" | grep -qE '\brm\b.+-[^[:space:]]*[rR]'; then
    printf '%s' "$c" | grep -qE '/(home|etc|usr|var|boot|root|bin|sbin|lib|sys|proc)' \
      && echo "BLOCKED rm-rf-system" && return
  fi
  # ── HIGH ──────────────────────────────────────────────────────
  printf '%s' "$c" | grep -qE '(curl|wget).+\|[[:space:]]*(bash|sh|python[0-9]?|node)\b' \
    && echo "HIGH remote-exec" && return
  printf '%s' "$c" | grep -qE 'git +push.+(-f|--force)\b' \
    && echo "HIGH git-force-push" && return
  printf '%s' "$c" | grep -qE '\brm\b.+-[^[:space:]]*[rR]' \
    && echo "HIGH rm-recursive" && return
  # Writes to system dirs (exclude redirects to /dev/null — with or without spaces)
  if printf '%s' "$c" | grep -vE '>\s*/dev/null' | grep -vE '2>\s*/dev/null' | grep -qE '> */(etc|usr|var|boot|root|bin|sbin|lib|proc|sys|dev)'; then
    echo "HIGH system-write" && return
  fi
  printf '%s' "$c" | grep -qE '\bsudo\b.+\b(rm|dd|mkfs)\b' \
    && echo "HIGH sudo-destruct" && return
  # ── MED ────────────────────────────────────────────────────────
  printf '%s' "$c" | grep -qE '\b(npm|pip3?|yarn|pnpm|cargo) +(install|add|update|upgrade)\b' \
    && echo "MED pkg-install" && return
  printf '%s' "$c" | grep -qE '\bgit +(commit|push|reset|rebase|merge)\b' \
    && echo "MED git-write" && return
  printf '%s' "$c" | grep -qE '\brm\b' \
    && echo "MED file-delete" && return
  printf '%s' "$c" | grep -qE '\bmv\b +' \
    && echo "MED file-move" && return
  printf '%s' "$c" | grep -qE '\b(systemctl|service)\b.+(start|stop|restart)\b' \
    && echo "MED service-ctrl" && return
  printf '%s' "$c_head" | grep -qE ' >[^>]' \
    && ! printf '%s' "$c_head" | grep -qE '^[[:space:]]*(cat|echo|printf|ls|find)\b' \
    && echo "MED file-write" && return
  # ── LOW ────────────────────────────────────────────────────────
  echo "LOW ok"
}

