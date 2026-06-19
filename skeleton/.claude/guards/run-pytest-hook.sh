#!/usr/bin/env bash
# Sensor (Python): запускает pytest для изменённого файла.
# PostToolUse(Edit/Write) — Claude Code. afterFileEdit — Cursor.
# Mute the green: exit 0 без вывода при успехе. При провале → additionalContext.
#
# Зачем отдельный от run-test-hook.sh: у pytest нет нативного "related tests"
# (как vitest related). Базовый sensor зовёт `$TEST_CMD <file>` — для pytest это
# падает на не-тестовых файлах. Здесь выбор тестов решается режимом.
#
# Конфиг (.harness.conf):
#   WATCH_DIR    — директория наблюдения (напр. "src")
#   TEST_CMD     — команда pytest (напр. "uv run pytest -q" или "pytest -q")
#   TEST_WORKDIR — откуда запускать (по умолчанию REPO_ROOT)
#   PYTEST_MODE  — testmon | map (по умолчанию testmon)
#     testmon — pytest-testmon выбирает тесты по графу зависимостей.
#               Файл-аргумент НЕ передаётся (testmon сам знает что гонять).
#     map     — test_*.py → гоняем его; исходник foo.py → парный тест
#               (tests/test_foo.py | <dir>/test_foo.py); не найден → молчим.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

WATCH_DIR="${WATCH_DIR:-src}"
TEST_CMD="${TEST_CMD:-pytest -q}"
TEST_WORKDIR="${TEST_WORKDIR:-}"
PYTEST_MODE="${PYTEST_MODE:-testmon}"

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
[[ "$CHANGED_FILE" != *.py ]] && exit 0

WATCH_ABS="${REPO_ROOT}/${WATCH_DIR}"
[[ "$CHANGED_FILE" != "$WATCH_ABS"* ]] && [[ "$CHANGED_FILE" != "${WATCH_DIR}"* ]] && exit 0
[[ "$CHANGED_FILE" == *"__pycache__"* ]] && exit 0

if [[ -n "$TEST_WORKDIR" ]]; then
  cd "${REPO_ROOT}/${TEST_WORKDIR}"
else
  cd "$REPO_ROOT"
fi

RUN_TARGET=""
case "$PYTEST_MODE" in
  testmon)
    RUN_TARGET="--testmon"
    ;;
  map)
    base="$(basename "$CHANGED_FILE")"
    if [[ "$base" == test_*.py ]]; then
      RUN_TARGET="$CHANGED_FILE"
    else
      name="${base%.py}"
      for cand in "tests/test_${name}.py" "$(dirname "$CHANGED_FILE")/test_${name}.py"; do
        [[ -f "$cand" ]] && RUN_TARGET="$cand" && break
      done
      [[ -z "$RUN_TARGET" ]] && exit 0
    fi
    ;;
  *)
    exit 0
    ;;
esac

set +e
OUTPUT="$($TEST_CMD $RUN_TARGET 2>&1)"
EXIT_CODE=$?
set -e

[[ $EXIT_CODE -eq 0 ]] && exit 0

echo "$OUTPUT" | tail -30 >&2
BASENAME="$(basename "$CHANGED_FILE")"
python3 -c "
import json
msg = 'pytest FAILED после правки ${BASENAME}. Почини ошибки выше прежде чем продолжить.'
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': msg}}))
"
exit 1
