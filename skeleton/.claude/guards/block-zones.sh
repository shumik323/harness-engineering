#!/usr/bin/env bash
# Guard: блокирует запись в READONLY_ZONES.
# Claude Code вызывает при PostToolUse(Write/Edit).
# Возвращает exit 2 → Claude видит ошибку и не продолжает запись.
#
# Переменные окружения (из .harness.conf или env):
#   READONLY_ZONES — пробел-разделённый список директорий (напр. "dist storybook-static")
#   REPO_ROOT      — корень репо (дефолт: git rev-parse --show-toplevel)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

READONLY_ZONES="${READONLY_ZONES:-dist}"

# Путь к файлу который Claude пытается записать — приходит как первый аргумент
# Claude Code передаёт file_path через stdin (JSON) или $1 в зависимости от hook-типа.
# Поддерживаем оба варианта.
if [[ $# -ge 1 ]]; then
  TARGET_FILE="$1"
else
  # Читаем JSON из stdin, извлекаем file_path
  INPUT=$(cat)
  TARGET_FILE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
fi

if [[ -z "$TARGET_FILE" ]]; then
  exit 0  # Нет пути — пропускаем
fi

for zone in $READONLY_ZONES; do
  ZONE_ABS="${REPO_ROOT}/${zone}"
  # Проверяем что TARGET_FILE начинается с пути зоны
  if [[ "$TARGET_FILE" == "$ZONE_ABS"* ]] || [[ "$TARGET_FILE" == "${zone}"* ]]; then
    echo "GUARD BLOCKED: '${zone}/' is a read-only zone (generated files)." >&2
    echo "Use the build command instead of writing directly." >&2
    exit 2
  fi
done

exit 0
