#!/usr/bin/env bash
# Sensor: запускает тесты для изменённых файлов.
# PostToolUse(Edit/Write) — Claude Code. afterFileEdit — Cursor.
# Mute the green: exit 0 без вывода при успехе.
# При провале: additionalContext → system reminder в агент.
#
# Конфиг (.harness.conf):
#   WATCH_DIR — директория (напр. "packages/ui-kit/lib")
#   TEST_CMD  — команда тестов (напр. "npx vitest related --run")
#   TEST_WORKDIR — откуда запускать TEST_CMD (напр. "packages/ui-kit")

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

WATCH_DIR="${WATCH_DIR:-src}"
TEST_CMD="${TEST_CMD:-echo 'TEST_CMD not set'}"
TEST_WORKDIR="${TEST_WORKDIR:-}"

export HOOK_INPUT
HOOK_INPUT="$(cat || true)"

[[ -z "${HOOK_INPUT// }" ]] && exit 0

CHANGED_FILE="$(python3 <<'PY'
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

[[ -z "$CHANGED_FILE" ]] && exit 0

WATCH_ABS="${REPO_ROOT}/${WATCH_DIR}"
[[ "$CHANGED_FILE" != "$WATCH_ABS"* ]] && [[ "$CHANGED_FILE" != "${WATCH_DIR}"* ]] && exit 0
[[ "$CHANGED_FILE" == *"__tests__"* ]] && exit 0
[[ "$CHANGED_FILE" == *"__snapshots__"* ]] && exit 0

if [[ -n "$TEST_WORKDIR" ]]; then
  cd "${REPO_ROOT}/${TEST_WORKDIR}"
else
  cd "$REPO_ROOT"
fi

set +e
OUTPUT="$($TEST_CMD "$CHANGED_FILE" 2>&1)"
EXIT_CODE=$?
set -e

[[ $EXIT_CODE -eq 0 ]] && exit 0

echo "$OUTPUT" | tail -30 >&2
BASENAME="$(basename "$CHANGED_FILE")"
python3 -c "
import json
msg = 'Tests FAILED for ${BASENAME}. Fix the errors above before continuing.'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))
"
exit 1
