#!/usr/bin/env bash
# Smoke test: проверяет что харнесс работает как задумано.
# Запускать после setup и после любого рефактора структуры.
#
# Гонять В ИНСТАНСЕ (проект с раскатанным харнессом), не в репе-шаблоне: тут
# нет ни .harness.conf, ни .claude/guards/, и проверять нечего. Запуск не там
# даёт exit 3 «ничего не проверено» — не зелёный (нечего проверять ≠ всё живо)
# и не красный (кривой запуск ≠ поломанный харнесс).
#
# Состав проверок здесь не перечисляем: список из восьми пунктов пережил рост до
# семнадцати и стал описывать не тот скрипт. Что проверяется — печатают [PASS]-строки
# прогона, они и есть реестр.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARDS="${REPO_ROOT}/.claude/guards"
PASS=0
FAIL=0

# NB: PASS=$((...)) не ((PASS++)) — `((expr))` возвращает exit 1 когда результат 0,
# и под `set -e` это роняет скрипт на первом же ok()/fail() (счётчик стартует с 0).
ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  [SKIP] $1"; }

echo "=== verify-harness ==="
echo ""

# 0. Запущен не в инстансе, а в самом шаблоне? Отдельный выход. Раньше тут был FAIL,
# то есть шаблон вечно «красный» на собственной проверке, хотя ломать в нём нечего.
# Признак шаблона — `.harness.conf.example` рядом (в инстанс он не доставляется ни
# одним каналом) или каталог `skeleton/` выше.
CONF="${REPO_ROOT}/.harness.conf"
# `copier.yml` этажом выше — мы внутри skeleton самого шаблона. Признак нужен
# отдельно: форк кладёт в skeleton готовый `.harness.conf`, и заготовка по
# старому признаку («конфига нет») выглядела инстансом.
if [[ -f "${REPO_ROOT}/../copier.yml" ]] \
   || { [[ ! -f "$CONF" ]] \
        && { [[ -f "${REPO_ROOT}/.harness.conf.example" ]] || [[ -d "${REPO_ROOT}/skeleton" ]]; }; }; then
  echo "  [SKIP] это шаблон харнесса, не проект — .harness.conf нет, раскатывать нечего."
  echo ""
  echo "Ничего не проверено. Смотри по назначению:"
  echo "  инстанс    → cd <проект> && bash scripts/verify-harness.sh"
  echo "  сам шаблон → bash scripts/verify-bootstrap.sh    (раскатка bootstrap'ом)"
  echo "               bash scripts/verify-copier.sh       (раскатка Copier'ом)"
  echo "               bash scripts/check-docs-reality.sh  (доки против кода)"
  exit 3
fi

# 1. .harness.conf
if [[ -f "$CONF" ]]; then
  source "$CONF"
  ok ".harness.conf найден и читается"
else
  fail ".harness.conf не найден в ${REPO_ROOT}"
  echo ""
  echo "Создай его из примера в шаблоне харнесса:"
  echo "  cp <harness-template>/skeleton/.harness.conf.example .harness.conf"
  echo "  # Заполни WATCH_DIR, READONLY_ZONES, TEST_CMD, GATE_CMD"
  exit 1
fi

# 2. guard существует и исполняем
GUARD="${REPO_ROOT}/.claude/guards/block-zones.sh"
if [[ -x "$GUARD" ]]; then
  ok "block-zones.sh исполняем"
else
  fail "block-zones.sh не найден или не исполняем: ${GUARD}"
fi

# 3. guard блокирует readonly зону
if [[ -n "${READONLY_ZONES:-}" ]]; then
  FIRST_ZONE=$(echo "$READONLY_ZONES" | awk '{print $1}')
  TEST_FILE="${REPO_ROOT}/${FIRST_ZONE}/test-verify.txt"

  echo "{\"tool_input\": {\"path\": \"${TEST_FILE}\"}}" | bash "$GUARD" >/dev/null 2>&1 || GUARD_EXIT=$?
  GUARD_EXIT=${GUARD_EXIT:-0}

  if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "guard блокирует readonly зону '${FIRST_ZONE}' (exit 2)"
  else
    fail "guard НЕ заблокировал readonly зону '${FIRST_ZONE}' (exit ${GUARD_EXIT})"
  fi
else
  fail "READONLY_ZONES не задан в .harness.conf"
fi

# 4. guard пропускает разрешённый путь
if [[ -n "${WATCH_DIR:-}" ]]; then
  ALLOWED_FILE="${REPO_ROOT}/${WATCH_DIR}/some-component.vue"
  echo "{\"tool_input\": {\"path\": \"${ALLOWED_FILE}\"}}" | bash "$GUARD" >/dev/null 2>&1 || GUARD_EXIT2=$?
  GUARD_EXIT2=${GUARD_EXIT2:-0}

  if [[ "$GUARD_EXIT2" -ne 2 ]]; then
    ok "guard пропускает разрешённый путь '${WATCH_DIR}' (exit ${GUARD_EXIT2})"
  else
    fail "guard ошибочно блокирует разрешённый путь '${WATCH_DIR}'"
  fi
else
  fail "WATCH_DIR не задан в .harness.conf"
fi

# 5. sensor существует
SENSOR="${REPO_ROOT}/.claude/guards/run-test-hook.sh"
if [[ -x "$SENSOR" ]]; then
  ok "run-test-hook.sh исполняем"
else
  fail "run-test-hook.sh не найден или не исполняем: ${SENSOR}"
fi

# 6. load-context.sh (опционально)
LOADER="${REPO_ROOT}/scripts/load-context.sh"
if [[ -f "$LOADER" ]]; then
  ok "load-context.sh найден (опционально)"
else
  echo "  [SKIP] load-context.sh не найден — SessionStart без долгосрочной памяти"
fi

# 7. gate: защита от петли. На stop_hook_active gate обязан выйти 0, не блокируя
# GATE_CMD — иначе Stop-хук уходит в бесконечный цикл. Саму проверку он при
# этом ВЫПОЛНЯЕТ и печатает итог: молчаливый пропуск неотличим от успеха.
#
# Гоняем на ПОДСТАВНОМ REPO_ROOT с `GATE_CMD="exit 9"`, а не на конфиге проекта.
# Причина: на настоящем конфиге исход один и тот же и когда защита работает, и когда
# её нет — GATE_CMD проходит, gate возвращает 0. Проверка была бы вакуумной (проверено
# мутацией: защиту убрал, тест остался зелёным). Команда, которая гарантированно падает,
# делает две ветки различимыми: 0 = не запускалась, 2 = запустилась.
GATE="${REPO_ROOT}/.claude/guards/gate.sh"
if [[ -x "$GATE" ]]; then
  GATE_SANDBOX="$(mktemp -d)"
  echo 'GATE_CMD="exit 9"' > "${GATE_SANDBOX}/.harness.conf"
  GATE_EXIT=0
  printf '%s' '{"stop_hook_active": true}' \
    | REPO_ROOT="$GATE_SANDBOX" bash "$GATE" >/dev/null 2>&1 || GATE_EXIT=$?
  rm -rf "$GATE_SANDBOX"
  if [[ "$GATE_EXIT" -eq 0 ]]; then
    ok "gate.sh: защита от петли держит (stop_hook_active → ход не блокируется)"
  else
    fail "gate.sh на stop_hook_active вернул ${GATE_EXIT}: Stop-хук уйдёт в цикл"
  fi

  # И не молчит: exit 0 при красной проверке неотличим от «гейт прошёл».
  GATE_SANDBOX="$(mktemp -d)"
  echo 'GATE_CMD="exit 9"' > "${GATE_SANDBOX}/.harness.conf"
  LOUD="$(printf '%s' '{"stop_hook_active": true}' \
    | REPO_ROOT="$GATE_SANDBOX" bash "$GATE" 2>&1 || true)"
  rm -rf "$GATE_SANDBOX"
  if [[ -n "${LOUD// }" ]]; then
    ok "gate.sh сообщает о красной проверке, даже когда не блокирует"
  else
    fail "gate.sh пропустил красную проверку МОЛЧА — неотличимо от успеха"
  fi
  if [[ -z "${GATE_CMD:-}" ]]; then
    echo "  [SKIP] GATE_CMD в .harness.conf пуст — Ярус 2 ничего не проверяет"
  fi
else
  fail "gate.sh не найден или не исполняем: ${GATE}"
fi

# 8. /note capture skill (append.sh исполняем).
# Путь именно в .claude/ проекта: раньше тут стоял ${REPO_ROOT}/skeleton/... — в любом
# инстансе такой папки нет, и проверка краснела всегда.
NOTE_APPEND="${REPO_ROOT}/.claude/skills/note/append.sh"
if [[ -x "$NOTE_APPEND" ]]; then
  ok "/note capture skill: append.sh исполняем"
else
  fail "/note append.sh не найден или не исполняем: ${NOTE_APPEND}"
fi

# 5. дочерние sensor-хуки на месте
for hook in run-test-hook.sh run-pytest-hook.sh; do
  if [[ -x "${GUARDS}/${hook}" ]]; then
    ok "${hook} исполняем"
  else
    fail "${hook} не найден или не исполняем: ${GUARDS}/${hook}"
  fi
done

# 8. sensor-диспетчер
DISPATCH="${GUARDS}/sensor.sh"
if [[ -x "$DISPATCH" ]]; then
  ok "sensor.sh (диспетчер) исполняем"
else
  fail "sensor.sh не найден или не исполняем: ${DISPATCH}"
fi

# 9. диспетчер молчит на неизвестном расширении и не падает
DISPATCH_EXIT=0
echo "{\"tool_input\": {\"file_path\": \"${REPO_ROOT}/README.md\"}}" | bash "$DISPATCH" >/dev/null 2>&1 || DISPATCH_EXIT=$?
if [[ "$DISPATCH_EXIT" -eq 0 ]]; then
  ok "sensor.sh fail-open на нерелевантном файле (exit 0)"
else
  fail "sensor.sh упал на нерелевантном файле (exit ${DISPATCH_EXIT})"
fi

# 10-12. Роутинг sensor'а (фикстура: временная репа).
# Проверяем три сценария:
#   - монорепа JS: тесты запускаются в БЛИЖАЙШЕМ воркспейсе, не в корне
#   - Python: тесты в воркспейсе с pyproject.toml
#   - legacy-конфиг (одностековый TEST_CMD, без JS_*): продолжает работать
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "${FIXTURE}/apps/web/src" "${FIXTURE}/apps/api/tests"
: > "${FIXTURE}/package.json"
: > "${FIXTURE}/apps/web/package.json"
: > "${FIXTURE}/apps/web/src/Btn.tsx"
: > "${FIXTURE}/apps/api/pyproject.toml"
: > "${FIXTURE}/apps/api/svc.py"
: > "${FIXTURE}/apps/api/tests/test_svc.py"

# Конфиг фикстуры в том же ${VAR:-} стиле, что и настоящий: иначе source затрёт env.
cat > "${FIXTURE}/.harness.conf" <<'CONF'
PY_WATCH_DIR="${PY_WATCH_DIR:-}"
PY_TEST_CMD="${PY_TEST_CMD:-}"
PY_TEST_WORKDIR="${PY_TEST_WORKDIR:-}"
PYTEST_MODE="${PYTEST_MODE:-map}"
JS_WATCH_DIR="${JS_WATCH_DIR:-}"
JS_TEST_CMD="${JS_TEST_CMD:-}"
JS_TEST_WORKDIR="${JS_TEST_WORKDIR:-}"
WATCH_DIR="${WATCH_DIR:-}"
TEST_CMD="${TEST_CMD:-}"
TEST_WORKDIR="${TEST_WORKDIR:-}"
SENSOR_MAP="${SENSOR_MAP:-}"
CONF

# Пробник вместо реального раннера: пишет свой cwd и молчит (mute the green).
# $PWD, а не `pwd -P`: mktemp на macOS отдаёт путь через симлинк (/var → /private/var),
# и физический путь не совпал бы с ожидаемым.
cat > "${FIXTURE}/probe.sh" <<'PROBE'
echo "$PWD" > "$(dirname "$0")/probe-out"
PROBE

probe_workspace() { # $1 = изменённый файл, $2 = имя переменной с командой
  rm -f "${FIXTURE}/probe-out"
  echo "{\"tool_input\": {\"file_path\": \"${FIXTURE}/${1}\"}}" \
    | env REPO_ROOT="$FIXTURE" "${2}=bash ${FIXTURE}/probe.sh" \
      bash "$DISPATCH" >/dev/null 2>&1 || true
  [[ -f "${FIXTURE}/probe-out" ]] && cat "${FIXTURE}/probe-out" || echo "<не запускался>"
}

JS_WS="$(probe_workspace "apps/web/src/Btn.tsx" JS_TEST_CMD)"
if [[ "$JS_WS" == "${FIXTURE}/apps/web" ]]; then
  ok "sensor.sh: .tsx → тесты в ближайшем JS-воркспейсе (apps/web)"
else
  fail "sensor.sh: .tsx ушёл не в тот воркспейс: ожидалось ${FIXTURE}/apps/web, получено ${JS_WS}"
fi

PY_WS="$(probe_workspace "apps/api/svc.py" PY_TEST_CMD)"
if [[ "$PY_WS" == "${FIXTURE}/apps/api" ]]; then
  ok "sensor.sh: .py → тесты в ближайшем Python-воркспейсе (apps/api)"
else
  fail "sensor.sh: .py ушёл не в тот воркспейс: ожидалось ${FIXTURE}/apps/api, получено ${PY_WS}"
fi

# legacy: одностековый конфиг (TEST_CMD, JS_* пусты) — файл в корневом воркспейсе
: > "${FIXTURE}/root-file.ts"
LEGACY_WS="$(probe_workspace "root-file.ts" TEST_CMD)"
if [[ "$LEGACY_WS" == "${FIXTURE}" ]]; then
  ok "sensor.sh: legacy TEST_CMD без JS_* работает (корневой воркспейс)"
else
  fail "sensor.sh: legacy TEST_CMD сломан: ожидалось ${FIXTURE}, получено ${LEGACY_WS}"
fi

# SENSOR_MAP: явный workdir из карты бьёт автоопределение по манифесту
mkdir -p "${FIXTURE}/custom"
probe_map() { # $1 = файл, $2 = переменная команды, $3 = карта
  rm -f "${FIXTURE}/probe-out"
  echo "{\"tool_input\": {\"file_path\": \"${FIXTURE}/${1}\"}}" \
    | env REPO_ROOT="$FIXTURE" "${2}=bash ${FIXTURE}/probe.sh" SENSOR_MAP="$3" \
      bash "$DISPATCH" >/dev/null 2>&1 || true
  [[ -f "${FIXTURE}/probe-out" ]] && cat "${FIXTURE}/probe-out" || echo "<не запускался>"
}

MAP_WS="$(probe_map "apps/web/src/Btn.tsx" JS_TEST_CMD "apps/web js custom")"
if [[ "$MAP_WS" == "${FIXTURE}/custom" ]]; then
  ok "sensor.sh: SENSOR_MAP workdir бьёт автоопределение (custom вместо apps/web)"
else
  fail "sensor.sh: SENSOR_MAP workdir не сработал: ожидалось ${FIXTURE}/custom, получено ${MAP_WS}"
fi

# SENSOR_MAP: папка явно отдана другому стеку → sensor молчит
OWN_WS="$(probe_map "apps/web/src/Btn.tsx" JS_TEST_CMD "apps/web py")"
if [[ "$OWN_WS" == "<не запускался>" ]]; then
  ok "sensor.sh: SENSOR_MAP владение — .tsx в py-папке молчит"
else
  fail "sensor.sh: SENSOR_MAP владение нарушено — .tsx в py-папке запустил тесты в ${OWN_WS}"
fi

# Ярус 3 активирован. Проверка нужна именно здесь, а не только в verify-bootstrap:
# тот смотрит на РОЖДЕНИЕ инстанса, а `.git/hooks` не версионируется — после `git clone`
# хука нет ни у кого, кроме того, кто гонял bootstrap. Документация при этом продолжает
# обещать проверку на push, и отличить «ярус прошёл» от «яруса нет» нечем.
PP_LOGIC="${GUARDS}/pre-push.sh"
PP_HOOK="${REPO_ROOT}/.git/hooks/pre-push"
if [[ ! -f "$PP_LOGIC" ]]; then
  fail "ярус 3: нет CORE-логики ${PP_LOGIC#"$REPO_ROOT"/} — перекати инстанс"
elif [[ ! -d "${REPO_ROOT}/.git" ]]; then
  skip "ярус 3: не git-репозиторий, ставить хук некуда"
elif [[ ! -x "$PP_HOOK" ]]; then
  fail "ярус 3 не подключён: нет исполняемого .git/hooks/pre-push — push ничем не проверяется"
elif ! grep -q "guards/pre-push.sh" -- "$PP_HOOK"; then
  fail "ярус 3: .git/hooks/pre-push не зовёт CORE-логику — на push идёт что-то другое"
else
  ok "ярус 3: .git/hooks/pre-push подключён и зовёт guards/pre-push.sh"
fi

# Дрейф CORE. Часть файлов защищена от `copier update` (`_skip_if_exists`), чтобы
# инстанс мог дорабатывать их под себя. Плата — расхождение с шаблоном, которого в диффе
# обновления не видно вовсе. Детектор уже есть (`harness-status.sh` в репозитории шаблона),
# ему не хватало повода запуститься: здесь и есть то место, где спрашивают состояние.
#
# DIVERGED и MISSING разведены НАМЕРЕННО. Расхождение — законное состояние (ради него защита
# и заводилась), и если красить им смоук, его выключат целиком вместе с верными пунктами.
# А вот пропавший CORE-файл — поломка доставки, и это FAIL.
LOCAL_CONF="${HARNESS_LOCAL_CONF:-${HOME:-}/.harness/$(basename "$REPO_ROOT").conf}"
# shellcheck source=/dev/null
[[ -f "$LOCAL_CONF" ]] && source "$LOCAL_CONF"
STATUS_SH="${HARNESS_TEMPLATE_PATH:-}/scripts/harness-status.sh"
if [[ -z "${HARNESS_TEMPLATE_PATH:-}" ]]; then
  skip "дрейф CORE не проверен: HARNESS_TEMPLATE_PATH не задан в ${LOCAL_CONF}"
elif [[ ! -f "$STATUS_SH" ]]; then
  fail "дрейф CORE: ${HARNESS_TEMPLATE_PATH} не похож на клон шаблона — нет scripts/harness-status.sh"
else
  DRIFT_OUT="$(bash "$STATUS_SH" "$REPO_ROOT" 2>&1 || true)"
  GONE="$(printf '%s\n' "$DRIFT_OUT" | awk '$1 == "MISSING" { printf "%s ", $2 }')"
  DIVERGED="$(printf '%s\n' "$DRIFT_OUT" | grep -E '^  DIVERGED ' || true)"
  if [[ -n "$GONE" ]]; then
    fail "дрейф CORE: CORE-файлов нет в инстансе: ${GONE% }"
  elif [[ -n "$DIVERGED" ]]; then
    ok "дрейф CORE: MISSING нет (расхождения ниже — не провал, решение владельца)"
    printf '%s\n' "$DIVERGED" | sed 's/^  DIVERGED /  [DRIFT] расходится с шаблоном: /'
    echo "          подъём наверх — harness-contribute.sh в репозитории шаблона"
  else
    ok "дрейф CORE: инстанс совпадает с шаблоном"
  fi
fi

echo ""
echo "=== Результат: ${PASS} pass / ${FAIL} fail ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
