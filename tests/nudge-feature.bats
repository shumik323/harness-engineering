#!/usr/bin/env bats
# Ветка «фича -> зови /feature» в nudge.sh. Хук UserPromptSubmit: exit 0 всегда (exit 2 стёр бы
# промпт), молчит на не-фиче, ветка по тикету работает только с непустым TICKET_PATTERN.
#
# Имена латиницей намеренно — bats 1.14 ломается на кириллице в заголовке @test.

setup() {
  SCRIPT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)/skeleton/.claude/guards/nudge.sh"
  export REPO_ROOT="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO_ROOT"
}

nudge() { printf '{"prompt":"%s"}' "$1" | bash "$SCRIPT"; }

@test "feature word: nudge to /feature" {
  run nudge "сделай фичу"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/feature"* ]]
}

@test "ticket with pattern in conf: nudge" {
  echo 'TICKET_PATTERN="MD-[0-9]+"' > "$REPO_ROOT/.harness.conf"
  run nudge "MD-1234 поправь"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/feature"* ]]
}

@test "ticket with empty pattern: silent" {
  echo 'TICKET_PATTERN=""' > "$REPO_ROOT/.harness.conf"
  run nudge "MD-1234 поправь"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ticket without conf: silent" {
  run nudge "MD-1234 поправь"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bug prompt: silent" {
  echo 'TICKET_PATTERN="MD-[0-9]+"' > "$REPO_ROOT/.harness.conf"
  run nudge "почини баг в списке"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "boundary branch intact" {
  run nudge "добавь api endpoint"
  [ "$status" -eq 0 ]
  [[ "$output" == *"boundary"* ]]
  [[ "$output" != *"/feature"* ]]
}

@test "empty stdin: exit 0" {
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
}
