#!/usr/bin/env bash
# Самопроверка второго канала доставки (Copier). Прогон: bash scripts/verify-copier.sh
#
# `verify-bootstrap.sh` гоняет только bootstrap-канал, и это стоило пяти битых ссылок:
# `_exclude: scripts` резал каталог у copier-инстансов, а самопроверка была зелёной.
# Источник истины — CORE_PATHS: файл объявлен CORE → оба канала обязаны его привезти.
#
# `--vcs-ref HEAD` обязателен: без него Copier для git-шаблона рендерит последний ТЕГ, и
# проверка отчитывалась бы о состоянии полугодовой давности. С флагом берётся рабочее дерево,
# включая незакоммиченное (проверено прогоном: untracked-файл в skeleton доезжает, а
# незакоммиченное правило `_exclude` его отсекает).

set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

check() {
  if [[ "$2" == "$3" ]]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1 — ожидалось [$3], получено [$2]"
    FAILED=1
  fi
}

command -v copier >/dev/null || {
  echo "нужен copier: uv tool install copier" >&2
  echo "Проверка Copier-канала НЕ выполнена — это не зелёный, а отсутствие проверки." >&2
  exit 1
}

# shellcheck source=lib/layers.sh
. "$TPL/scripts/lib/layers.sh"

WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"   # /var → /private/var на macOS, иначе пути расходятся строкой
OUT="$WORK/rendered"

echo "== Рендер рабочего дерева Copier'ом =="

# project_name обязателен: без него copier падает с `Question "project_name" is required`,
# каталог не создаётся, и подавленный вывод читается как «рендер прошёл, файлов нет».
(cd "$TPL" && copier copy --trust --defaults --overwrite --vcs-ref HEAD \
  --data project_name=probe --data lang=vue . "$OUT") >/dev/null 2>&1
RENDER_RC=$?

[[ $RENDER_RC -eq 0 ]] && R=ok || R="rc=$RENDER_RC"
check "рендер прошёл" "$R" ok

if [[ $RENDER_RC -ne 0 ]]; then
  echo "Рендер упал — остальные проверки пропущены, чтобы не отчитаться зелёным о непроверенном." >&2
  rm -rf "$WORK"
  exit 1
fi

echo "== CORE доезжает Copier'ом =="

MISSING=""
for path in "${CORE_PATHS[@]}"; do
  [[ -f "$OUT/$path" ]] || MISSING="$MISSING $path"
done
[[ -z "$MISSING" ]] && R=все || R="нет:$MISSING"
check "все ${#CORE_PATHS[@]} путей CORE_PATHS в рендере" "$R" все

# Exec-бит ровный по обоим каналам: bootstrap ставит +x, расхождение прав даёт «у меня работает».
NOEXEC=""
for path in "${CORE_PATHS[@]}"; do
  case "$path" in
    *.sh) [[ -x "$OUT/$path" ]] || NOEXEC="$NOEXEC $path" ;;
  esac
done
[[ -z "$NOEXEC" ]] && R=все || R="без +x:$NOEXEC"
check "скрипты CORE исполняемы" "$R" все

echo "== Личное и не-CORE не протекает =="

# Личное не должно ехать: заполненный WIKI_PATH в шаблоне = личный путь в каждом инстансе.
# Закомментированная строка — документация, а не утечка: пример заполнения
# живёт в самом конфиге. Ищем ПРИСВАИВАНИЕ, не упоминание.
WIKI_LEAK="$(grep -rlE '^[[:space:]]*WIKI_PATH="[^"]+"' "$OUT" 2>/dev/null | grep -c . )"
check "заполненного WIKI_PATH в рендере нет" "$WIKI_LEAK" 0

# ADR-13: роли-агенты instance-owned.
[[ -d "$OUT/.claude/agents" ]] && R=протёк || R=нет
check ".claude/agents не доставлен" "$R" нет

TPL_LEAK="$(find "$OUT" -name '*.template' -type f 2>/dev/null | grep -c . )"
check "*.template не протёк" "$TPL_LEAK" 0

# Две проверки, а не одна. Утверждение «чужого нет» на ПУСТОМ каталоге верно и бессмысленно:
# `find | grep -vc` на пустом входе даёт 0, и проверка проходила бы, даже если не доехало
# НИЧЕГО (нашло независимое ревью 14.08 мутацией «убрать vue.md из доставки»). Сначала
# убеждаемся, что нужный слой на месте, и только потом — что лишнего нет.
LANG_FILES="$(find "$OUT/.claude/rules/lang" -type f 2>/dev/null | grep -c . )"
check "нужный языковой слой доехал (rules/lang непуст)" "$([[ "$LANG_FILES" -gt 0 ]] && echo да || echo нет)" да

# `shell.md` из вычета исключён намеренно: он CORE и едет ВСЕГДА (харнесс любого проекта
# состоит из .sh). Утечкой считается только чужой ЯЗЫК ПРОЕКТА — vue-инстанс не должен
# получить dotnet.md. Без этого исключения проверка требовала бы не доставлять CORE-файл.
LANG_LEAK="$(find "$OUT/.claude/rules/lang" -type f 2>/dev/null | grep -v 'shell\.md' | grep -vc 'vue' )"
check "чужие языковые слои не протекли (shell.md — CORE, не утечка)" "$LANG_LEAK" 0

SHELL_RULE="$([[ -f "$OUT/.claude/rules/lang/shell.md" ]] && echo да || echo нет)"
check "shell.md доехал независимо от lang" "$SHELL_RULE" да

echo
echo "Рендер: $OUT"
if [[ $FAILED -eq 0 ]]; then
  echo "ВСЁ ЗЕЛЁНОЕ"
  rm -rf "$WORK"
  exit 0
fi
echo "ЕСТЬ ПРОВАЛЫ — рендер оставлен для разбора" >&2
exit 1
