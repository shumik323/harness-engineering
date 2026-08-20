#!/usr/bin/env bash
# Gate (Ярус 2): repo-wide проверка БЕЗ полных тестов — type-check + lint + build.
# Sensor (run-test-hook.sh) пофайловый и реактивный — он НЕ ловит type-ошибки
# по проекту, линт, сборку и поломки конфигов/зависимостей. Это делает gate.
# Тесты на Stop намеренно не гоняем (медленно для каждого хода) — их закрывает
# sensor. Полный прогон тестов добавляется отдельно на pre-push (Ярус 3, GATE_TEST_CMD,
# см. .husky/pre-push) — там медленно допустимо.
#
# Использование:
#   Stop hook (Claude Code) — stdin JSON со `stop_hook_active`. exit 2 → ход
#     не завершается, stderr идёт агенту. Защита от петли: stop_hook_active==true → exit 0.
#   husky pre-push / руками — без stdin. exit != 0 → push блокируется.
#
# Конфиг (.harness.conf):
#   GATE_CMD     — проверка без тестов (напр. "turbo type-check lint build"). Пусто → fail-open,
#                  но при СУЩЕСТВУЮЩЕМ .harness.conf ещё и строка в stderr: пустая команда
#                  при заполненном конфиге — выключенный гейт, а не «харнесс не настроен».
#   GATE_WORKDIR — откуда запускать (по умолчанию REPO_ROOT).

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
CONF_FOUND=no
[[ -f "$CONF" ]] && { source "$CONF"; CONF_FOUND=yes; }

GATE_CMD="${GATE_CMD:-}"
GATE_WORKDIR="${GATE_WORKDIR:-}"

# stdin есть только когда нас вызвали как Stop hook. Руками/husky — пусто.
export HOOK_INPUT
HOOK_INPUT="$(cat 2>/dev/null || true)"

# Защита от петли: если агент уже в forced-continuation после нашего же блока —
# второй раз не блокируем, иначе бесконечный цикл (см. gotcha про Stop).
if [[ ! "$HOOK_INPUT" =~ ^[[:space:]]*$ ]]; then
  STOP_ACTIVE="$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('stop_hook_active', False))
except Exception:
    print(False)
" 2>/dev/null || echo False)"
fi

# Fail-open, но НЕ одинаково молча. Два разных случая:
#   .harness.conf нет           → харнесс не настроен, это законно → тихий exit 0;
#   .harness.conf есть, CMD пуст→ гейт выключен втихую → говорим одной строкой.
# Второй случай раньше давал такой же молчаливый зелёный, как первый.
if [[ "$GATE_CMD" =~ ^[[:space:]]*$ ]]; then
  if [[ "$CONF_FOUND" == yes ]]; then
    OFF="GATE_CMD в .harness.conf пуст — Ярус 2 не проверяет ничего (type-check/lint/build)."
    echo "HARNESS: ${OFF}" >&2
    # Как Stop-hook мы выходим с 0, а stderr при exit 0 пользователю не показывают —
    # дублируем в systemMessage (та же причина, что в блоке WARN ниже).
    if [[ ! "$HOOK_INPUT" =~ ^[[:space:]]*$ ]]; then
      OFF="$OFF" python3 -c 'import json, os; print(json.dumps({"systemMessage": "HARNESS: " + os.environ["OFF"]}, ensure_ascii=False))' 2>/dev/null || true
    fi
  fi
  exit 0
fi

# --- Дрейф среды: ПРЕДУПРЕЖДЕНИЕ, не блок ------------------------------------
# Зелёный gate на чужой среде — ложная уверенность, красный на исправном коде —
# остановленная работа. Второе дороже, поэтому расхождения печатаем и идём дальше.
WARN=""

if [[ -f "${REPO_ROOT}/.nvmrc" ]] && command -v node >/dev/null 2>&1; then
  WANT="$(tr -d ' \t\rv\n' < "${REPO_ROOT}/.nvmrc")"
  HAVE="$(node -v | tr -d 'v')"
  # Сравнение по МАЖОРУ: патч-дрейф (локально 24.18, в CI 24.13) ничего не ломает,
  # а предупреждение на каждый Stop обесценивается шумом.
  if [[ -n "$WANT" && "${HAVE%%.*}" != "${WANT%%.*}" ]]; then
    WARN+="gate гоняется на Node ${HAVE}, .nvmrc ожидает ${WANT} — расхождение с CI. "
  fi
fi

# Сверка «критерий приёмки ↔ тест»: сигнал ЗДЕСЬ, блокировка на Ярусе 3.
# Блокировать на Stop нельзя — проверка краснела бы на том же ходе, где спека с новыми AC
# написана, а тест по ней ещё нет, то есть наказывала бы за spec-first. Но узнавать о дыре
# только на push поздно: между спекой и push помещается вся работа. Поэтому здесь — строка
# предупреждения, в `pre-push.sh` — тот же скрипт с блокировкой.
# Только как Stop-хук: pre-push зовёт gate.sh шагом 1 и сам же гоняет эту сверку шагом 3,
# без условия сообщение печаталось бы дважды.
if [[ ! "$HOOK_INPUT" =~ ^[[:space:]]*$ && -x "${REPO_ROOT}/scripts/check-ac-refs.sh" ]]; then
  AC_OUT=""
  AC_OUT="$(bash "${REPO_ROOT}/scripts/check-ac-refs.sh" --quiet 2>&1 </dev/null)" || true
  # Первая строка вывода скрипта — итог вида «AC БЕЗ ТЕСТА: N при пороге M».
  AC_FIRST="$(printf '%s' "$AC_OUT" | grep -m1 'AC БЕЗ ТЕСТА' || true)"
  [[ -n "$AC_FIRST" ]] && WARN+="${AC_FIRST} Блокировать это будет pre-push, не сейчас. "
  # Скрипт спроектирован «fail-open, но ВСЛУХ»: при ненастроенности он говорит
  # об этом в stderr. Захватив вывод и взяв из него одну строку, мы этот голос
  # глушили — ярус выключен и неотличим от пройденного (rules/common/testing.md).
  AC_MUTE="$(printf '%s' "$AC_OUT" | grep -m1 'не задан\|не работает' || true)"
  [[ -n "$AC_MUTE" ]] && WARN+="${AC_MUTE} "

fi

# node_modules старее lock-файла → проверка судит о состоянии, которого нет.
if [[ -f "${REPO_ROOT}/package-lock.json" \
   && -f "${REPO_ROOT}/node_modules/.package-lock.json" \
   && "${REPO_ROOT}/package-lock.json" -nt "${REPO_ROOT}/node_modules/.package-lock.json" ]]; then
  WARN+="package-lock.json новее установленных зависимостей — нужен npm ci, gate может врать. "
fi

if [[ -n "$WARN" ]]; then
  echo "HARNESS WARNING: ${WARN}" >&2
  # Как Stop-hook мы выходим с 0, а stderr при exit 0 пользователю не показывают —
  # дублируем в systemMessage. Без stdin (husky/руками) хватает stderr выше.
  if [[ ! "$HOOK_INPUT" =~ ^[[:space:]]*$ ]]; then
    WARN="$WARN" python3 -c 'import json, os; print(json.dumps({"systemMessage": "HARNESS WARNING: " + os.environ["WARN"]}, ensure_ascii=False))' 2>/dev/null || true
  fi
fi

if [[ -n "$GATE_WORKDIR" ]]; then
  cd "${REPO_ROOT}/${GATE_WORKDIR}"
else
  cd "$REPO_ROOT"
fi

set +e
OUTPUT="$(eval "$GATE_CMD" 2>&1)"
EXIT_CODE=$?
set -e

[[ $EXIT_CODE -eq 0 ]] && exit 0

echo "$OUTPUT" | tail -40 >&2
echo "" >&2

# Агент уже в forced-continuation после нашего же блока: второй раз не блокируем,
# иначе бесконечный цикл. Но и не молчим — молчаливый пропуск неотличим от
# успеха, а `rules/common/testing.md` требует, чтобы проверка падала, а не
# исчезала. Поэтому итог печатаем всегда, а ход отпускаем.
if [[ "${STOP_ACTIVE:-False}" == "True" ]]; then
  echo "GATE FAILED (exit ${EXIT_CODE}): \`${GATE_CMD}\` не прошёл. Ход НЕ блокируется — это повторный Stop, — но проверка красная." >&2
  exit 0
fi

echo "GATE FAILED (exit ${EXIT_CODE}): \`${GATE_CMD}\` не прошёл. Почини ошибки выше прежде чем завершить ход или push." >&2
exit 2
