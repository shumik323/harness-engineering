#!/usr/bin/env bash
# Добавить запись в лог проекта, не перезаписывая файл.
#
# Usage:  bash scripts/log-append.sh <файл-с-записью>
#         LOG_FILE=docs/other.md bash scripts/log-append.sh entry.md
#
# Зачем скрипт вместо Edit: лог растёт до десятков килобайт, а Edit дифает файл
# целиком — на большом логе тул висит минутами. Правило в rules/common/workflow.md
# требует append именно поэтому, а не из вкуса.
#
# Куда вставляет: перед первым заголовком записи (`## `), потому что лог читается
# сверху и свежее должно быть первым. Если заголовков ещё нет — дописывает в конец.
# «Append» здесь значит «не перезапись», а не «в конец файла».
#
# Почему не `sed -i`: на macOS он требует аргумент суффикса (`sed -i ''`), а на
# Linux — нет. Скрипт уезжает в инстансы на обеих системах, поэтому awk плюс
# временный файл: одно поведение везде.

set -u

# Лог по замыслу живёт в вике: `end-session` велит писать в `$WIKI_PATH/log.md`
# именно этим скриптом. Про личный слой скрипт не знал и падал на `docs/log.md` —
# то есть штатный путь из скила не работал. Читаем тот же слой, что load-context.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOCAL_CONF="${HARNESS_LOCAL_CONF:-${HOME:-}/.harness/$(basename "$REPO_ROOT").conf}"
# shellcheck source=/dev/null
[ -f "$LOCAL_CONF" ] && . "$LOCAL_CONF"

if [ -n "${LOG_FILE:-}" ]; then
  :
elif [ -n "${WIKI_PATH:-}" ]; then
  LOG_FILE="${WIKI_PATH}/log.md"
else
  LOG_FILE="docs/log.md"
fi
ENTRY="${1:-}"

if [ -z "$ENTRY" ]; then
  printf 'log-append: нужен файл с записью\n  usage: bash scripts/log-append.sh <файл>\n' >&2
  exit 1
fi

if [ ! -f "$ENTRY" ]; then
  printf 'log-append: файла с записью нет: %s\n' "$ENTRY" >&2
  exit 1
fi

if [ ! -s "$ENTRY" ]; then
  printf 'log-append: файл с записью пуст: %s — в лог ничего не добавлено\n' "$ENTRY" >&2
  exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
  printf 'log-append: лога нет: %s\n  создай его или задай LOG_FILE\n' "$LOG_FILE" >&2
  exit 1
fi

ENTRY_LINES=$(wc -l < "$ENTRY" | tr -d ' ')
BEFORE_LINES=$(wc -l < "$LOG_FILE" | tr -d ' ')

# Имя через mktemp, а не `.$$`: PID предсказуем, и в каталоге, куда может писать кто-то ещё,
# предсказуемое имя — окно для подмены симлинком (CWE-377). Рядом с логом, а не в /tmp:
# переименование в конце должно остаться в пределах одной файловой системы.
TMP="$(mktemp "${LOG_FILE}.log-append.XXXXXX")" || {
  printf 'log-append: не удалось создать временный файл рядом с логом\n' >&2
  exit 1
}
# $TMP разворачиваем СЕЙЧАС намеренно: cleanup обязан удалить именно этот файл, а не то,
# на что переменная будет указывать в момент выхода.
# Директива подавления держится ОТДЕЛЬНОЙ строкой и несёт только код: пояснение в той же
# строке ломает разбор (SC1125 «Invalid key=value pair»), shellcheck отбрасывает остаток
# директивы, и подавление молча перестаёт работать — замер 18.08.
# shellcheck disable=SC2064
trap "rm -f '$TMP'" EXIT INT TERM

awk -v entry="$ENTRY" '
  !placed && /^## / {
    while ((getline line < entry) > 0) print line
    print ""
    placed = 1
  }
  { print }
  END {
    # Заголовков записей в логе ещё нет — дописываем в конец, чтобы запись не пропала.
    if (!placed) {
      print ""
      while ((getline line < entry) > 0) print line
    }
  }
' "$LOG_FILE" > "$TMP" || {
  printf 'log-append: awk не справился, лог не тронут\n' >&2
  exit 1
}

AFTER_LINES=$(wc -l < "$TMP" | tr -d ' ')

# Проверка, что запись реально попала: молча потерянный вход хуже отказа.
# Считаем НАПЕЧАТАННОЕ, а не переданное — иначе счётчик подтвердит полноту, которой нет.
if [ "$AFTER_LINES" -le "$BEFORE_LINES" ]; then
  printf 'log-append: после вставки лог не вырос (%s → %s) — отказ, файл не тронут\n' \
    "$BEFORE_LINES" "$AFTER_LINES" >&2
  exit 1
fi

mv "$TMP" "$LOG_FILE"
trap - EXIT INT TERM

printf 'log-append: +%s строк в %s (%s → %s)\n' \
  "$((AFTER_LINES - BEFORE_LINES))" "$LOG_FILE" "$BEFORE_LINES" "$AFTER_LINES"
