#!/usr/bin/env bash
# Guard: блокирует запись в READONLY_ZONES.
# PreToolUse(Edit/Write/Bash) — Claude Code. postToolUse — Cursor.
# exit 2 → блокирует в обоих контекстах.
#
# Конфиг (.harness.conf):
#   READONLY_ZONES — пробел-разделённый список (напр. "dist storybook-static")

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

READONLY_ZONES="${READONLY_ZONES:-dist}"

export HOOK_INPUT
HOOK_INPUT="$(cat || true)"

[[ -z "${HOOK_INPUT// }" ]] && exit 0

# Recursive walk: ищем file_path в любом месте JSON
TARGET_FILE="$(python3 <<'PY'
import json, os

raw = os.environ.get("HOOK_INPUT", "")
if not raw.strip():
    print(""); raise SystemExit

try:
    data = json.loads(raw)
except (json.JSONDecodeError, TypeError):
    print(""); raise SystemExit

def walk(obj, acc):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ("file_path", "filePath", "path", "target_file") and isinstance(v, str):
                acc.append(v)
            walk(v, acc)
    elif isinstance(obj, list):
        for v in obj:
            walk(v, acc)

paths = []
walk(data, paths)
print(paths[0] if paths else "")
PY
)"

# Bash tool: читаем command и grep на READONLY_ZONES
if [[ -z "$TARGET_FILE" ]]; then
  BASH_CMD="$(python3 -c "
import json, os
raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
    print(data.get('tool_input', {}).get('command', ''))
except:
    print('')
")"
  for zone in $READONLY_ZONES; do
    if echo "$BASH_CMD" | grep -qE "(^|[/ >|&])${zone}(/|\s|\"|'|$)"; then
      echo "GUARD BLOCKED: Bash command targets '${zone}/' (read-only zone)." >&2
      echo "Use the build command instead of writing directly." >&2
      exit 2
    fi
  done
  exit 0
fi

for zone in $READONLY_ZONES; do
  ZONE_ABS="${REPO_ROOT}/${zone}"
  if [[ "$TARGET_FILE" == "$ZONE_ABS"* ]] || [[ "$TARGET_FILE" == "${zone}"* ]]; then
    echo "GUARD BLOCKED: '${zone}/' is a read-only zone (generated files)." >&2
    echo "Use the build command instead of writing directly." >&2
    exit 2
  fi
done

exit 0
