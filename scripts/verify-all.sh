#!/usr/bin/env bash
# Ярус 3 репы-шаблона: все самопроверки одной командой.
#
# Зачем отдельный скрипт: у шаблона шесть проверок в шести файлах, и «прогнать всё» до сих
# пор означало помнить четыре команды. Забытая — это молчаливая дыра ровно того класса, против
# которого написаны сами проверки.
#
# Что тут НЕ проверяется и почему: смоук `verify-harness.sh` — он про раскатанный харнесс,
# а в репе-шаблоне его нет (код 3 «ничего не проверено»). Ярусы 1-2 (sensor/gate по файлам)
# шаблону не нужны: тут нет билда и нет пофайловых тестов, единица проверки — вся репа.
#
# Порядок от дешёвого к дорогому, но БЕЗ fail-fast: полный прогон ~28 секунд, и увидеть все
# провалы разом дороже, чем сэкономить двадцать. Замер 14.08: shell 1s · copier 2s · purity 2s ·
# bootstrap 11s · docs-reality 13s · bats 22s (последний внутри сам зовёт copier и purity — это не дубль по
# смыслу: он сверяет их ЧИСЛА с числами в доках).

set -uo pipefail

# Git выставляет хукам GIT_DIR. В обычном чекауте он относительный (`.git`) и безвреден, в
# worktree — абсолютный путь к настоящему репо. Фикстуры ниже делают `git init` в песочнице:
# с унаследованным GIT_DIR это переинициализировало боевой репо (core.bare=true, чужой
# user.email, ветки фикстур). Проверки сами находят свой репо, наследовать нечего.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FAILED=0
NAMES=()
CODES=()

run_step() {
  local title="$1" script="$2"
  printf '\n=== %s (%s) ===\n' "$title" "$script"
  local code=0
  bash "scripts/${script}" || code=$?
  NAMES+=("$title")
  CODES+=("$code")
  [[ "$code" -eq 0 ]] || FAILED=1
}

run_step "Синтаксис shell"     lint-shell.sh
run_step "Канал Copier"        verify-copier.sh
run_step "Чистота CORE"        lint-core-purity.sh
run_step "Канал bootstrap"     verify-bootstrap.sh
run_step "Доки против кода"    check-docs-reality.sh
run_step "Тесты скриптов"    run-bats.sh   # 22s — самый дорогой, потому последний

printf '\n===== ИТОГ =====\n'
i=0
while [[ "$i" -lt "${#NAMES[@]}" ]]; do
  if [[ "${CODES[$i]}" -eq 0 ]]; then
    printf '  ok    %s\n' "${NAMES[$i]}"
  else
    printf '  ПРОВАЛ %s (код %s)\n' "${NAMES[$i]}" "${CODES[$i]}"
  fi
  i=$((i + 1))
done

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nВСЁ ЗЕЛЁНОЕ\n'
else
  printf '\nЕСТЬ ПРОВАЛЫ — push не пойдёт, пока красное.\n'
fi
exit "$FAILED"
