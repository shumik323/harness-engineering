#!/usr/bin/env bash
# Smoke test: проверяет что харнесс работает как задумано.
# Запускать после setup и после любого рефактора структуры.
#
# Тесты:
#   1. .harness.conf существует и читается
#   2. guard блокирует readonly зону (exit 2)
#   3. guard пропускает разрешённый путь (exit 0)
#   4. sensor существует и исполняем
#   5. load-context.sh существует (опционально)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }

echo "=== verify-harness ==="
echo ""

# 1. .harness.conf
CONF="${REPO_ROOT}/.harness.conf"
if [[ -f "$CONF" ]]; then
  source "$CONF"
  ok ".harness.conf найден и читается"
else
  fail ".harness.conf не найден в ${REPO_ROOT}"
  echo ""
  echo "Создай его из примера:"
  echo "  cp skeleton/.harness.conf.example .harness.conf"
  echo "  # Заполни WATCH_DIR, READONLY_ZONES, TEST_CMD, WIKI_PATH"
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

  GUARD_OUT=$(echo "{\"tool_input\": {\"path\": \"${TEST_FILE}\"}}" | bash "$GUARD" 2>&1) || GUARD_EXIT=$?
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
  GUARD_OUT2=$(echo "{\"tool_input\": {\"path\": \"${ALLOWED_FILE}\"}}" | bash "$GUARD" 2>&1) || GUARD_EXIT2=$?
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

# 7. /note capture skill в skeleton (append.sh исполняем)
NOTE_APPEND="${REPO_ROOT}/skeleton/.claude/skills/note/append.sh"
if [[ -x "$NOTE_APPEND" ]]; then
  ok "skeleton /note capture skill: append.sh исполняем"
else
  fail "skeleton /note append.sh не найден или не исполняем: ${NOTE_APPEND}"
fi

echo ""
echo "=== Результат: ${PASS} pass / ${FAIL} fail ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
