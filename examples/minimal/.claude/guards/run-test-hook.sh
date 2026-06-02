#!/usr/bin/env bash
# Sensor: запускает TEST_CMD после Edit/Write в WATCH_DIR. Mute the green.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${SCRIPT_DIR}/../../.harness.conf"

[[ -f "$CONF" ]] && source "$CONF" || exit 0
[[ -z "${WATCH_DIR:-}" ]] && exit 0

INPUT=$(cat)
CHANGED_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('path',''))" 2>/dev/null || true)

[[ -z "$CHANGED_FILE" ]] && exit 0
[[ "$CHANGED_FILE" != *"${WATCH_DIR}"* ]] && exit 0
[[ "$CHANGED_FILE" == *"__tests__"* ]] && exit 0
[[ "$CHANGED_FILE" == *"__snapshots__"* ]] && exit 0

if ${TEST_CMD} "$CHANGED_FILE" > /dev/null 2>&1; then
  exit 0
else
  echo "[SENSOR] Tests failed for: ${CHANGED_FILE}" >&2
  ${TEST_CMD} "$CHANGED_FILE" >&2 || true
  exit 1
fi
