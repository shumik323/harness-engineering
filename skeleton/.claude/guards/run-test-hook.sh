#!/usr/bin/env bash
# Sensor: запускает тесты для изменённых файлов.
# Claude Code вызывает при PostToolUse(Edit/Write).
# Mute the green — молчит при успехе, сигналит только при провале.
#
# Переменные окружения (из .harness.conf или env):
#   WATCH_DIR — директория за которой следим (напр. "packages/ui-kit/lib")
#   TEST_CMD  — команда тестов, принимает список файлов (напр. "vitest related --run")
#   REPO_ROOT — корень репо

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

WATCH_DIR="${WATCH_DIR:-src}"
TEST_CMD="${TEST_CMD:-echo 'TEST_CMD not set'}"

# Читаем изменённый файл из аргументов или stdin (JSON)
if [[ $# -ge 1 ]]; then
  CHANGED_FILE="$1"
else
  INPUT=$(cat)
  CHANGED_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
fi

if [[ -z "$CHANGED_FILE" ]]; then
  exit 0
fi

WATCH_ABS="${REPO_ROOT}/${WATCH_DIR}"

# Игнорируем файлы вне WATCH_DIR
if [[ "$CHANGED_FILE" != "$WATCH_ABS"* ]] && [[ "$CHANGED_FILE" != "${WATCH_DIR}"* ]]; then
  exit 0
fi

# Игнорируем тест-файлы и снапшоты (они сами и есть тест)
if [[ "$CHANGED_FILE" == *"__tests__"* ]] || [[ "$CHANGED_FILE" == *"__snapshots__"* ]]; then
  exit 0
fi

# Запускаем тесты. Mute the green: stdout подавляем, stderr — нет.
cd "$REPO_ROOT"
if $TEST_CMD "$CHANGED_FILE" > /dev/null 2>&1; then
  exit 0  # Успех — молчим
else
  echo "SENSOR: tests failed for ${CHANGED_FILE}" >&2
  # Повторяем с выводом чтобы Claude увидел детали
  $TEST_CMD "$CHANGED_FILE" >&2 || true
  exit 1
fi
