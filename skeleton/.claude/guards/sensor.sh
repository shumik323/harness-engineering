#!/usr/bin/env bash
# Sensor-диспетчер: роутит PostToolUse(Edit|Write) в нужный дочерний sensor.
# Универсален: обычный однопакетный репозиторий, один стек, монорепа с несколькими
# воркспейсами — одна и та же проводка, ничего перенастраивать не нужно.
#
# Два уровня роутинга:
#   1. ЯЗЫК — по расширению изменённого файла:
#        *.py                          → run-pytest-hook.sh (у pytest нет "related tests")
#        *.ts/tsx/js/jsx/mjs/cjs/vue   → run-test-hook.sh
#   2. ВОРКСПЕЙС — подъём вверх по дереву от файла до ближайшего манифеста
#      (package.json / pyproject.toml / setup.cfg / setup.py). Найденная директория —
#      корень воркспейса, оттуда запускаются тесты.
#        - обычный проект: ближайший манифест = корень репы → поведение как раньше;
#        - монорепа: у каждого приложения свой манифест → тесты гоняются в нём,
#          новый воркспейс подхватывается сам, без правки .harness.conf.
#
# Конфиг (.harness.conf) — все значения в форме ${VAR:-default}, потому что диспетчер
# передаёт WATCH_DIR/TEST_CMD дочернему хуку через env, а хук сорсит conf поверх:
#   SENSOR_MAP   — ЯВНАЯ карта «папка → стек [→ workdir]» (см. ниже). Задана и
#                  совпала → бьёт автоопределение. Пусто / нет совпадения → автоматика.
#   PY_TEST_CMD  — команда pytest ("uv run pytest -q"). Пусто → .py молчат.
#   JS_TEST_CMD  — команда JS-тестов ("npx vitest related --run").
#                  Пусто → фолбэк на legacy TEST_CMD (одностековые конфиги работают как раньше).
#   PY_WATCH_DIR / JS_WATCH_DIR   — сузить наблюдение (пусто → весь воркспейс).
#   PY_TEST_WORKDIR / JS_TEST_WORKDIR — явный workdir на весь стек (пусто → карта/автоопределение).
#
# SENSOR_MAP — строки вида `<glob-путь> <стек> [workdir]`, первый матч выигрывает:
#   SENSOR_MAP="
#   apps/api     py
#   apps/web     js
#   packages/*   js
#   docs         none
#   "
#   - glob матчится по пути от корня репы (и по самой папке, и по её поддереву);
#   - стек: py | js | none (none = папка явно не тестируется);
#   - файл попал в папку ЧУЖОГО стека (например .py в js-папке) → молчим:
#     карта — это заявление владения, не подсказка;
#   - workdir опционален: пусто → автоопределение по манифесту внутри этой папки.
#
# Fail-open везде: нет команды, нет манифеста, нет директории → exit 0, правка не блокируется.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# Дочерние хуки ищем рядом с собой, а не в REPO_ROOT: диспетчер и хуки — один пакет,
# и он должен работать, даже когда наблюдаемое дерево не совпадает с деревом харнесса.
GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

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

# Вендорное/сгенерированное — не наш случай (guard такое блокирует на записи,
# но файл мог прийти из другого инструмента).
case "$CHANGED_FILE" in
  */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/.turbo/*|*/__pycache__/*|*/.venv/*) exit 0 ;;
esac

# Путь может прийти абсолютным (Claude Code) или относительным (другие клиенты).
ABS_FILE="$CHANGED_FILE"
[[ "$ABS_FILE" != /* ]] && ABS_FILE="${REPO_ROOT}/${ABS_FILE}"
REL_FILE="${ABS_FILE#"$REPO_ROOT"/}"

# Явная карта SENSOR_MAP: первый матч → "стек workdir". Нет карты / нет матча → exit 1.
map_lookup() {
  local rel="$1" line pat stack wd
  [[ -z "${SENSOR_MAP:-}" ]] && return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    [[ -z "${line// }" ]] && continue
    read -r pat stack wd <<<"$line"
    [[ -z "$pat" || -z "$stack" ]] && continue
    # Незакавыченный $pat в case — намеренно: это glob-паттерн из карты.
    case "$rel" in
      $pat|$pat/*) printf '%s %s' "$stack" "${wd:-}"; return 0 ;;
    esac
  done <<<"$SENSOR_MAP"
  return 1
}

MAP_STACK=""
MAP_WD=""
if MAP_HIT="$(map_lookup "$REL_FILE")"; then
  read -r MAP_STACK MAP_WD <<<"$MAP_HIT"
fi

# Подъём от файла к корню репы в поисках манифеста воркспейса.
# stdout: путь воркспейса относительно REPO_ROOT ("" = сам корень репы).
# exit 1 = манифест не найден вообще.
find_workspace() {
  local dir="$1"; shift
  local manifest rel
  while :; do
    for manifest in "$@"; do
      if [[ -f "${dir}/${manifest}" ]]; then
        rel="${dir#"$REPO_ROOT"}"
        printf '%s' "${rel#/}"
        return 0
      fi
    done
    [[ "$dir" == "$REPO_ROOT" || "$dir" == "/" ]] && return 1
    dir="$(dirname "$dir")"
  done
}

# WATCH_DIR для дочернего хука. Тот фильтрует файл по префиксу и подставляет дефолт
# "src" на ПУСТОЙ строке — поэтому воркспейс-корень репы ("") пустым не передать.
# Отдаём абсолютный REPO_ROOT: дочерний хук сверяет ещё и сырой префикс
# ([[ "$CHANGED_FILE" != "${WATCH_DIR}"* ]]), и абсолютный путь файла его проходит.
watch_dir_for() {
  [[ -n "${1:-}" ]] && printf '%s' "$1" || printf '%s' "$REPO_ROOT"
}

workdir_missing() {
  [[ -n "${1:-}" && ! -d "${REPO_ROOT}/${1}" ]]
}

# Зона наблюдения для дочернего хука. Карта совпала → фильтрация путей уже сделана
# картой, дочернему отдаём весь корень (иначе он отсеял бы файл по workdir'у,
# который при явном override может не содержать сам файл).
watch_for_child() { # $1 = WS
  if [[ -n "$MAP_STACK" ]]; then
    printf '%s' "$REPO_ROOT"
  else
    watch_dir_for "$1"
  fi
}

case "$CHANGED_FILE" in
  *.py)
    # Папка явно отдана другому стеку (или none) → молчим: карта — заявление владения.
    [[ -n "$MAP_STACK" && "$MAP_STACK" != "py" ]] && exit 0
    # Строго PY_TEST_CMD, без фолбэка на TEST_CMD: legacy одностековый JS-конфиг
    # держит в TEST_CMD vitest — .py туда отправлять нельзя.
    [[ -z "${PY_TEST_CMD:-}" || -z "${PY_TEST_CMD// }" ]] && exit 0

    # Приоритет workdir: явный на стек > из карты > автоопределение по манифесту.
    WS="${PY_TEST_WORKDIR:-$MAP_WD}"
    if [[ -z "$WS" ]]; then
      WS="$(find_workspace "$(dirname "$ABS_FILE")" pyproject.toml setup.cfg setup.py)" || exit 0
    fi
    workdir_missing "$WS" && exit 0

    exec env \
      WATCH_DIR="${PY_WATCH_DIR:-$(watch_for_child "$WS")}" \
      TEST_CMD="${PY_TEST_CMD}" \
      TEST_WORKDIR="${WS}" \
      PYTEST_MODE="${PYTEST_MODE:-map}" \
      bash "${GUARD_DIR}/run-pytest-hook.sh" <<<"$HOOK_INPUT"
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.vue)
    # Папка явно отдана другому стеку (или none) → молчим: карта — заявление владения.
    [[ -n "$MAP_STACK" && "$MAP_STACK" != "js" ]] && exit 0
    # Фолбэк на legacy TEST_CMD/TEST_WORKDIR: одностековые конфиги, написанные
    # до диспетчера, продолжают работать без правки.
    CMD="${JS_TEST_CMD:-${TEST_CMD:-}}"
    [[ -z "${CMD// }" ]] && exit 0

    # Приоритет workdir: явный на стек > из карты > legacy > автоопределение по манифесту.
    WS="${JS_TEST_WORKDIR:-${MAP_WD:-${TEST_WORKDIR:-}}}"
    if [[ -z "$WS" ]]; then
      WS="$(find_workspace "$(dirname "$ABS_FILE")" package.json)" || exit 0
    fi
    workdir_missing "$WS" && exit 0

    exec env \
      WATCH_DIR="${JS_WATCH_DIR:-${WATCH_DIR:-$(watch_for_child "$WS")}}" \
      TEST_CMD="${CMD}" \
      TEST_WORKDIR="${WS}" \
      bash "${GUARD_DIR}/run-test-hook.sh" <<<"$HOOK_INPUT"
    ;;
esac

exit 0
