#!/usr/bin/env bash
# Guard: блокирует запись в READONLY_ZONES из .harness.conf
# Получает путь файла через stdin (JSON от Claude Code) или $1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/../../.harness.conf"

[[ -f "$CONF" ]] && source "$CONF" || { echo "[guard] .harness.conf not found" >&2; exit 0; }
[[ -z "${READONLY_ZONES:-}" ]] && exit 0

if [[ -n "${1:-}" ]]; then
  TARGET_FILE="$1"
else
  INPUT=$(cat)
  TARGET_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('path',''))" 2>/dev/null || true)
fi

[[ -z "$TARGET_FILE" ]] && exit 0

for zone in $READONLY_ZONES; do
  ZONE_ABS="${REPO_ROOT:-$(pwd)}/${zone}"
  if [[ "$TARGET_FILE" == "$ZONE_ABS"* ]] || [[ "$TARGET_FILE" == *"/${zone}/"* ]]; then
    echo "[GUARD] BLOCKED: ${TARGET_FILE} is in readonly zone '${zone}'" >&2
    exit 2
  fi
done
