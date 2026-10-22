#!/usr/bin/env bats
# Напоминание «спеки нет» в load-context.sh — только по флагу SPEC_FIRST.
#
# Зачем: `docs/specs/_template.md` едет в каждый инстанс, поэтому условие «есть каталог спек»
# включало строку «код не начинаем» в каждой сессии проекта, где спек не ведут. Тест закрепляет:
# без флага молчит, с флагом напоминает, а список активных спек выводится независимо от флага.
#
# Имена латиницей намеренно — bats 1.14 ломается на кириллице в заголовке @test.

setup() {
  SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/skeleton/scripts/load-context.sh"
  SANDBOX="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$SANDBOX/docs/specs"
  touch "$SANDBOX/docs/specs/_template.md"
  # Личный конфиг вне песочницы не должен подмешивать WIKI_PATH владельца.
  export HARNESS_LOCAL_CONF="${BATS_TEST_TMPDIR}/no-local.conf"
  export CLAUDE_PROJECT_DIR="$SANDBOX"
  # Флаг из окружения разработчика не должен решать исход «без флага».
  unset SPEC_FIRST
}

@test "no flag, no specs: no reminder" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"код не начинаем"* ]]
}

@test "flag in harness.conf: reminder shown" {
  printf 'SPEC_FIRST="yes"\n' > "$SANDBOX/.harness.conf"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"код не начинаем"* ]]
}

@test "flag other than yes: no reminder" {
  printf 'SPEC_FIRST="no"\n' > "$SANDBOX/.harness.conf"
  run bash "$SCRIPT"
  [[ "$output" != *"код не начинаем"* ]]
}

@test "active spec listed without flag" {
  printf -- '- [ ] AC-1\n' > "$SANDBOX/docs/specs/spec-probe.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec-probe.md"* ]]
  [[ "$output" != *"код не начинаем"* ]]
}
