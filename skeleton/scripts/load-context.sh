#!/usr/bin/env bash
# SessionStart hook: loads long-term memory into Claude's context.
# Reads WIKI_PATH from .harness.conf → outputs overview.md + tail of log.md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="${REPO_ROOT}/.harness.conf"

if [[ ! -f "$CONF" ]]; then
  echo "[load-context] .harness.conf not found at ${CONF} — skipping" >&2
  exit 0
fi

source "$CONF"

if [[ -z "${WIKI_PATH:-}" ]]; then
  echo "[load-context] WIKI_PATH not set in .harness.conf — skipping" >&2
  exit 0
fi

OVERVIEW="${WIKI_PATH}/overview.md"
LOG="${WIKI_PATH}/log.md"

echo "=== Project Context (loaded from TechWiki) ==="
echo ""

if [[ -f "$OVERVIEW" ]]; then
  echo "--- overview.md ---"
  cat "$OVERVIEW"
  echo ""
fi

if [[ -f "$LOG" ]]; then
  echo "--- log.md (last 30 lines) ---"
  tail -30 "$LOG"
  echo ""
fi

echo "=== End Context ==="
