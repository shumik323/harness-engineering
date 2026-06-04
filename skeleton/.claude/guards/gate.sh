#!/usr/bin/env bash
# Gate (Ярус 2/3): repo-wide проверка перед завершением хода и перед push.
# Sensor (run-test-hook.sh) пофайловый и реактивный — он НЕ ловит type-ошибки
# по проекту, линт, сборку и поломки конфигов/зависимостей. Это делает gate.
#
# Использование:
#   Stop hook (Claude Code) — stdin JSON со `stop_hook_active`. exit 2 → ход
#     не завершается, stderr идёт агенту. Защита от петли: stop_hook_active==true → exit 0.
#   husky pre-push / руками — без stdin. exit != 0 → push блокируется.
#
# Конфиг (.harness.conf):
#   GATE_CMD     — полная проверка (напр. "turbo type-check lint build"). Пусто → fail-open.
#   GATE_WORKDIR — откуда запускать (по умолчанию REPO_ROOT).

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CONF="${REPO_ROOT}/.harness.conf"
[[ -f "$CONF" ]] && source "$CONF"

GATE_CMD="${GATE_CMD:-}"
GATE_WORKDIR="${GATE_WORKDIR:-}"

# stdin есть только когда нас вызвали как Stop hook. Руками/husky — пусто.
export HOOK_INPUT
HOOK_INPUT="$(cat 2>/dev/null || true)"

# Защита от петли: если агент уже в forced-continuation после нашего же блока —
# второй раз не блокируем, иначе бесконечный цикл (см. gotcha про Stop).
if [[ -n "${HOOK_INPUT// }" ]]; then
  STOP_ACTIVE="$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('stop_hook_active', False))
except Exception:
    print(False)
" 2>/dev/null || echo False)"
  [[ "$STOP_ACTIVE" == "True" ]] && exit 0
fi

# Fail-open: gate не настроен → молчим (как sensor без TEST_CMD).
[[ -z "${GATE_CMD// }" ]] && exit 0

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
echo "GATE FAILED (exit ${EXIT_CODE}): \`${GATE_CMD}\` не прошёл. Почини ошибки выше прежде чем завершить ход или push." >&2
exit 2
