#!/usr/bin/env bash
# Sensor: запускает тесты для изменённых файлов.
# PostToolUse(Edit/Write) — Claude Code.
# Mute the green: exit 0 без вывода при успехе.
# При провале: additionalContext → system reminder в агент.
#
# Конфиг (.harness.conf):
#   WATCH_DIR — директория (напр. "packages/<пакет>/lib" или "src")
#   TEST_CMD  — команда тестов (напр. "npx vitest related --run")
#   TEST_WORKDIR — откуда запускать TEST_CMD (напр. "packages/<пакет>")

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

WATCH_DIR="${WATCH_DIR:-src}"
TEST_WORKDIR="${TEST_WORKDIR:-}"

# Пустой TEST_CMD — законная конфигурация, а не забытая настройка: у некоторых стеков нет
# пофайлового прогона (в .NET у `dotnet test` нет аналога "related tests"), и тесты там
# закрывает Ярус 3. Раньше вместо пустой команды подставлялся `echo 'TEST_CMD not set'`:
# он успешен, поэтому вывод глушился mute-the-green и в контекст не попадал — то есть хук
# просто исполнял бессмысленную команду на каждой правке. Выходим сразу.
[[ -z "${TEST_CMD:-}" ]] && exit 0

export HOOK_INPUT
HOOK_INPUT="$(cat || true)"

[[ "$HOOK_INPUT" =~ ^[[:space:]]*$ ]] && exit 0

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
# Тестовые файлы НЕ исключаем: правка проверки обязана эту проверку и запускать.
# `vitest related` по тесту находит его самого, по вспомогательному файлу —
# тесты, которые его импортируют. Исключение оставляло автора правила без
# обратной связи до самого конца хода.
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
