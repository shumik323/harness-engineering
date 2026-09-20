#!/usr/bin/env bash
# Закрывающая проверка Н1: доки не утверждают того, что перестало быть правдой.
# Прогон из корня harness-template.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

OK=0; FAIL=0; SKIPPED=0
check() { # имя · ожидание · факт
  if [[ "$2" == "$3" ]]; then printf '  ok   %s\n' "$1"; OK=$((OK+1))
  else printf 'FAIL   %s — ждали «%s», получили «%s»\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
# Проверка про ОПЕРАЦИОНКУ (`docs/plans/` в .gitignore) в клоне выполнена быть не может.
# Молчать нельзя — молчаливый пропуск неотличим от пройденной проверки. Краснеть тоже нельзя:
# отсутствие неверсионируемого файла не дефект. Поэтому третий исход, названный вслух.
# До 14.08 такого исхода не было, и скрипт давал 4 FAIL в любом клоне, кроме рабочей копии
# владельца: написанный против ложного зелёного, он выдавал ложный красный (ревью 14.08).
skip() { printf '  --   %s — пропущено: %s\n' "$1" "$2"; SKIPPED=$((SKIPPED+1)); }

# Носитель операционки. Есть в рабочей копии владельца, отсутствует в клоне — оба состояния
# законны, и от него зависит, какие проверки выполнимы.
TODO=docs/plans/TODO.md

# Публичные доки — читаются как факт, устаревшее утверждение в них равно лжи.
PUBLIC=(docs/architecture.md docs/decisions.md
        docs/specify-implement-review.md README.md CLAUDE.md)
# Рабочий лог — там цитата устаревшей строки законна («было X → стало Y»), поэтому
# цитаты и стрелки отфильтровываются, а голое утверждение всё равно ловится.
LOGS=(docs/plans/TODO.md docs/plans/2026-08-12-harness-master-plan.md)
# Только существующие: в клоне LOGS отсутствуют законно, и «нет самого дока» было бы ложью.
DOCS=("${PUBLIC[@]}")
for lf in "${LOGS[@]}"; do [[ -f "$lf" ]] && DOCS+=("$lf"); done

# 1. Устаревшие утверждения. Каждое было правдой и перестало.
for pat in "Не запушено" "три коммита" "28 тудушек" "dual-tool" "git вне скоупа" \
           "едут ровно три"; do
  P_HITS="$(grep -rn -- "$pat" "${PUBLIC[@]}" 2>/dev/null || true)"
  L_HITS="$(grep -rn -- "$pat" "${LOGS[@]}" 2>/dev/null \
            | grep -v '«\|→\|снято\|неверно\|была ложной\|разморожен' || true)"
  # ${pat} в скобках обязательно: bash 3.2 на macOS затягивает следующий многобайтный
  # символ в имя переменной → «unbound variable» на определённой переменной.
  check "нет устаревшего: ${pat}" "" "${P_HITS}${L_HITS}"
done

# 2. Числа проверок совпадают с прогоном. Число в доке = обещание, которое можно проверить.
BS="$(bash scripts/verify-bootstrap.sh 2>&1 | grep -c '^  ok ')"
# Якорь `^  ok ` обязателен: `grep -c ok` считал ЛЮБУЮ строку с этими буквами, а verify-copier
# печатает путь случайного temp-каталога — стоило `ok` попасть в `tmp.XXXX`, и число прыгало
# с 7 на 8. Проверка чисел сама давала случайный красный (поймано мутацией 13.08).
CP="$(bash scripts/verify-copier.sh 2>&1 | grep -c '^  ok ')"
if [[ -f "$TODO" ]]; then
  DOC_BS="$(grep -o 'verify-bootstrap` [0-9]\+ ok' "$TODO" | head -1 | grep -o '[0-9]\+' || true)"
  DOC_CP="$(grep -o 'verify-copier` [0-9]\+ ok' "$TODO" | head -1 | grep -o '[0-9]\+' || true)"
  check "verify-bootstrap: док = прогон" "$BS" "$DOC_BS"
  check "verify-copier: док = прогон" "$CP" "$DOC_CP"
else
  skip "verify-bootstrap: док = прогон" "нет $TODO (операционка вне git)"
  skip "verify-copier: док = прогон" "нет $TODO (операционка вне git)"
fi
printf '       факт прогона: verify-bootstrap %s ok · verify-copier %s ok\n' "$BS" "$CP"

# 3. Ссылки на файлы внутри репо резолвятся. Битая ссылка = та же ложь, что неверное число.
BROKEN=""
for f in "${DOCS[@]}"; do
  [[ -f "$f" ]] || { BROKEN="${BROKEN}${f}(нет самого дока) "; continue; }
  # markdown-ссылки вида [текст](путь) — только локальные, без http и без якорей
  while IFS= read -r link; do
    [[ -z "$link" ]] && continue
    [[ "$link" == http* || "$link" == \#* ]] && continue
    target="${link%%#*}"
    [[ -z "$target" ]] && continue
    # Ссылка относительна СВОЕМУ доку, а не корню репо: `[план](2026-08-12-...)` внутри
    # docs/plans/ резолвится в docs/plans/2026-08-12-..., иначе проверка даёт ложный красный.
    [[ "$target" == /* ]] || target="$(dirname "$f")/$target"
    [[ -e "$target" ]] || BROKEN="${BROKEN}${f} -> ${target} "
  done < <(grep -o '](\([^)]*\))' "$f" | sed 's/^](//; s/)$//')
done
check "локальные md-ссылки резолвятся" "" "$BROKEN"

# 4. Дерево в architecture.md не упоминает того, чего нет на диске.
MISSING=""
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  find . -name "$name" -not -path './.git/*' -print -quit | grep -q . || MISSING="$MISSING$name "
done < <(grep -o '[a-z0-9_-]\+\.sh' docs/architecture.md | sort -u)
check "все .sh из дерева architecture.md существуют" "" "$MISSING"

# 5. Обратное направление: существующий скрипт назван в дереве.
# Направление «упомянут → существует» (проверка 4) ловит битую ссылку, но НЕ ловит дрейф от
# нового файла: добавил скрипт, в доку не вписал — проверка молчит. Слепую зону нашло
# независимое ревью 13.08 ровно на том заходе, где эта проверка появилась: она сама не
# заметила собственного отсутствия в дереве.
UNLISTED=""
for f in scripts/*.sh scripts/lib/*.sh skeleton/.claude/guards/*.sh skeleton/scripts/*.sh; do
  [[ -e "$f" ]] || continue
  grep -q "$(basename "$f")" docs/architecture.md || UNLISTED="${UNLISTED}${f} "
done
check "каждый скрипт назван в дереве architecture.md" "" "$UNLISTED"

# 5б. То же обратное направление, но для НЕ-скриптов. Проверки 4 и 5 ходят по маске `*.sh`,
# поэтому весь `.md`-дрейф и новые каталоги проходили молча: ревью 14.08 нашло в дереве шесть
# отсутствующих позиций разом (`docs/specs/_template.md`, `agents/`, `python.md`, `.husky/`,
# `.copier-answers.yml.jinja`), и ни одна проверка их не видела.
#
# Область намеренно узкая: не «каждый .md в skeleton» (их десятки, дерево стало бы шумом), а
# позиции, чьё отсутствие и было дефектом — верхний уровень `skeleton/` и языковые слои.
# Источник — `git ls-files`, поэтому игнорируемое (`rules/lang/md-libs.md`) исключается само:
# в чистом клоне его нет, и требовать его в дереве значило бы врать про клон.
STRUCT_MISS=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  # depth-1 записи skeleton/: файлы по basename, каталоги как `имя/`
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    grep -qF -- "$item" docs/architecture.md || STRUCT_MISS="${STRUCT_MISS}${item} "
  done < <(
    git ls-files skeleton 2>/dev/null | awk -F/ 'NF>1 {print (NF>2 ? $2"/" : $2)}' | sort -u
    git ls-files 'skeleton/.claude/rules/lang/*.md' 2>/dev/null | xargs -n1 basename 2>/dev/null
    git ls-files 'skeleton/docs/specs/*.md' 2>/dev/null | xargs -n1 basename 2>/dev/null
  )
  check "верхний уровень skeleton и языковые слои названы в дереве" "" "$STRUCT_MISS"
else
  skip "верхний уровень skeleton и языковые слои названы в дереве" "не git-репозиторий"
fi

# 6. Перечисление шагов Яруса 3 нигде не короче самого яруса. Дрейф ловится вторым местом:
# диаграмма обновлена, а вторая копия списка — нет. Так и вскрылось на README 13.08: там Ярус 3
# остался четырёхшаговым после того, как сверка AC стала пятым шагом.
#
#
# Окно — строка и СЛЕДУЮЩАЯ, ровно две. Обе границы найдены ошибками:
#   `ln..ln+2` зеленело от слова `AC-ID` в несвязанной строке таблицы двумя рядами ниже —
#     перечисление Яруса 3 из трёх шагов проходило проверку, которая это и должна ловить
#     (нашло независимое ревью 14.08);
#   `ln` в одиночку дало ложный красный на README, где то же перечисление законно переносится
#     на вторую строку.
SHORT=""
while IFS=: read -r file ln _; do
  [[ -z "${file:-}" ]] && continue
  CTX="$(sed -n "${ln},$((ln + 1))p" "$file")"
  printf '%s' "$CTX" | grep -q 'AC' || SHORT="${SHORT}${file}:${ln} "
done < <(grep -rn 'секрет-скан' "${PUBLIC[@]}" 2>/dev/null || true)
check "перечисления Яруса 3 называют сверку AC" "" "$SHORT"

# 7. Назвал четыре яруса — скажи, что нулевой шаблон не ставит. Ярус 0 (pre-commit) заводит
# проект: линтер у каждого стека свой, bootstrap ставит только git-хук pre-push. Запрещать само
# число нельзя — как модель ярусов четыре, и оглавление вправе их перечислить. Ловится другое:
# перечисление БЕЗ оговорки, потому что оно читается как «четыре хука из коробки» (так и было
# в шапке README до 13.08).
TIER0=""
for f in "${PUBLIC[@]}"; do
  [[ -f "$f" ]] || continue
  grep -q 'четырёх ярусах\|четыре яруса' "$f" || continue
  grep -q 'Ярус 0.*\(не ставит\|заводит проект\)\|pre-commit.*\(не ставит\|заводит проект\)' "$f" \
    || TIER0="${TIER0}${f} "
done
check "документ с четырьмя ярусами оговаривает, что Ярус 0 не поставляется" "" "$TIER0"

# 8. У каждого дока из цикла доставки есть шаблон. Список рос (3 → 8), и всякая его копия в тексте
# устаревала молча; сверять надо цикл с диском, а не доку с памятью.
NODOC=""
DOC_LINE="$(grep -o 'for DOC in [A-Za-z0-9 _-]*' scripts/bootstrap.sh | head -1 | sed 's/for DOC in //')"
# Пустой разбор — провал, а не пропуск: цикл переписали, проверка перестала что-либо сверять и
# продолжила печатать `ok`. Это ровно тот false green, за которым весь этот скрипт и написан.
if [[ -z "$DOC_LINE" ]]; then
  check "цикл доставки доков найден в bootstrap.sh" "найден" "не найден"
else
  for d in $DOC_LINE; do
    [[ -f "skeleton/.claude/docs/${d}.md.template" ]] || NODOC="${NODOC}${d} "
  done
  check "у каждого дока из цикла bootstrap есть шаблон" "" "$NODOC"
fi

# 9. Открытые чекбоксы TODO живут в одном месте — иначе счёт двоится.
if [[ ! -f "$TODO" ]]; then
  skip "все открытые чекбоксы в секции «Остаток»" "нет $TODO (операционка вне git)"
  FIRST_OPEN=""; SECTION=""; SKIP_CB=yes
else
  SKIP_CB=no
fi
FIRST_OPEN="$(grep -n '^- \[ \]' "$TODO" 2>/dev/null | head -1 | cut -d: -f1)"
SECTION="$(grep -n '^## Остаток' "$TODO" 2>/dev/null | cut -d: -f1)"
# Ни одного открытого чекбокса — утверждение «все они в секции» верно на пустом множестве.
# Первая версия считала это провалом и дала ложный красный ровно на том заходе, где остаток
# закрылся: проверка наказывала за доделанную работу.
NOTE=""
if [[ "$SKIP_CB" == no ]]; then
  if [[ -z "$FIRST_OPEN" ]]; then R=да; NOTE="открытых чекбоксов в TODO нет"
  elif [[ -n "$SECTION" && "$FIRST_OPEN" -gt "$SECTION" ]]; then R=да
  else R=нет; fi
  check "все открытые чекбоксы в секции «Остаток»" "да" "$R"
  [[ -n "$NOTE" ]] && printf '       %s\n' "$NOTE"
fi

# 10. Ссылки ВНУТРИ skeleton на `.claude/docs/*.md`: либо док доставляется циклом bootstrap, либо
# ссылка помечена условной («приезжает с lang-pack», «если есть»). Проверка 3 сюда не доставала —
# она ходит по докам репозитория, а не по тому, что едет потребителю. Это ровно тот дефект,
# который закрывал коммит `8a5677a` (CORE ссылался на девять несуществующих файлов) и который
# после него ничем не охранялся. Окно — строка и следующая: оговорка часто на переносе.
DANGLING=""
DELIVERED2="$(grep -o 'for DOC in [A-Za-z0-9 _-]*' scripts/bootstrap.sh | head -1 | sed 's/for DOC in //')"
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  loc="${hit%%:*}"; rest="${hit#*:}"; lnum="${rest%%:*}"
  [[ "$lnum" =~ ^[0-9]+$ ]] || continue
  CTX="$(sed -n "${lnum},$((lnum + 1))p" "$loc" 2>/dev/null)"
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    name="$(basename "$ref" .md)"
    case " $DELIVERED2 " in *" $name "*) continue ;; esac
    printf '%s' "$CTX" | grep -q 'lang-pack\|если\|оттуда же' \
      || DANGLING="${DANGLING}${loc}:${lnum}(${name}) "
  done < <(printf '%s' "${hit#*:*:}" | grep -o '\.claude/docs/[A-Za-z0-9_-]\+\.md' | sort -u)
done < <(grep -rn '\.claude/docs/[A-Za-z0-9_-]\+\.md' skeleton/.claude/rules skeleton/.claude/skills \
           skeleton/.claude/docs skeleton/CLAUDE.md.template 2>/dev/null || true)
check "ссылки skeleton на доки: доставляется или помечена условной" "" "$DANGLING"

# 11. Роутер потребителя описывает те же хуки, что настроены. `CLAUDE.md` грузится у каждого
# потребителя КАЖДУЮ сессию, поэтому неверная таблица хуков — самая дорогая ложь в шаблоне:
# до 14.08 она вешала guard на PostToolUse (где блокировать уже нечего), Stop называла
# «предлагает обновить лог», а nudge, SessionEnd и PreToolUse(Bash) не упоминала вовсе.
HOOKDRIFT=""
SJ="skeleton/.claude/settings.json.template"; CT="skeleton/CLAUDE.md.template"
if [[ -f "$SJ" && -f "$CT" ]]; then
  for ev in PreToolUse PostToolUse Stop UserPromptSubmit SessionStart SessionEnd; do
    grep -q "\"${ev}\"" "$SJ" && IN_SJ=да || IN_SJ=нет
    grep -q "$ev" "$CT" && IN_CT=да || IN_CT=нет
    [[ "$IN_SJ" == "$IN_CT" ]] || HOOKDRIFT="${HOOKDRIFT}${ev}(настроен=${IN_SJ},описан=${IN_CT}) "
  done
else
  HOOKDRIFT="нет одного из файлов: ${SJ} ${CT}"
fi
check "хуки в CLAUDE.md.template = событиям settings.json.template" "" "$HOOKDRIFT"

# 12. Роутер называет все всегда-грузимые правила. `comments.md` доезжал обоими каналами и
# грузился у потребителя, а роутер перечислял пять правил из шести (ревью 14.08).
RULEDRIFT=""
for f in skeleton/.claude/rules/common/*.md; do
  [[ -e "$f" ]] || continue
  n="$(basename "$f" .md)"
  grep -q "$n" "$CT" || RULEDRIFT="${RULEDRIFT}${n} "
done
check "все правила rules/common названы в роутере" "" "$RULEDRIFT"

# 21. `@`-импортов нет НИ В ОДНОМ файле skeleton. Запрет живёт в CORE («грузит на старте, не
# лениво — для JIT не годится»), но охранял его только ассерт в `verify-bootstrap`, и тот смотрит
# на СГЕНЕРИРОВАННЫЙ `CLAUDE.md`. Файл, который не генерируется, был вне охраны целиком: в
# `PACKAGE_CLAUDE.md.template` `@.claude/docs/ARCHITECTURE.md` прожил незамеченным (ревью 14.08).
# Проверка идёт по исходникам, поэтому видит и то, что ни один канал не рендерит.
#
# Внутри ``` -блоков `@` не считается: там лежат ПРИМЕРЫ промптов, а `@file` в промпте, набранном
# руками, — законный синтаксис приложения файла к одному сообщению, не постоянный импорт. Без
# этого различия проверка краснела бы на примере в `REVIEW.md.template` и заставляла ломать
# правильный текст. Почтовые адреса гасит требование `.md` на конце и отсечка `слово@слово`.
ATIMPORT="$(python3 - <<'PY'
import os, re
pat = re.compile(r'(?<![A-Za-z0-9_.+-])@[A-Za-z0-9_./-]*\.md\b')
hits = []
for root, dirs, files in os.walk('skeleton'):
    for f in files:
        p = os.path.join(root, f)
        try:
            lines = open(p, encoding='utf-8').read().splitlines()
        except Exception:
            continue
        fenced = False
        for i, line in enumerate(lines, 1):
            if line.lstrip().startswith('```'):
                fenced = not fenced
                continue
            if fenced:
                continue
            if pat.search(line):
                hits.append(f'{p}:{i}')
print(' '.join(hits) + (' ' if hits else ''), end='')
PY
)"
check "@-импортов доков в skeleton нет" "" "$ATIMPORT"

# 22. Утечка внутренних имён в публичный репозиторий. `workflow.md` требует проверку
# публикуемости перед тегом, а механизма не было — только глазами.
#
# Список терминов живёт ВНЕ репозитория. Причина прямая: проверка, запрещающая строку, обязана
# эту строку содержать, поэтому тракаемый список сам был бы утечкой. Отсюда же ушёл паттерн
# устаревшего с кодовым именем инстанса из проверки 1.
# Нет файла → SKIP вслух, не зелёный: «список не найден» и «утечек нет» — разные ответы.
# В вывод идут только ИМЕНА ФАЙЛОВ, никогда сам термин: иначе лог прогона станет новой утечкой.
PRIV="${HARNESS_PRIVATE_TERMS:-${HOME:-}/.harness/$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")-private-terms.txt}"
if [[ ! -f "$PRIV" ]]; then
  skip "внутренних имён в трекаемых файлах нет" "нет ${PRIV} (список приватный, вне репозитория)"
else
  # Индекс и рабочее дерево расходятся: файл, удалённый или перенесённый и ещё не закоммиченный,
  # в `git ls-files` есть, а на диске нет. Молча проглотить такой вход нельзя — проверка стала бы
  # утверждать охват, которого не имеет. Считаем и называем числом.
  GONE=0
  while IFS= read -r -d '' tf; do
    [[ -f "$tf" ]] || GONE=$((GONE + 1))
  done < <(git ls-files -z 2>/dev/null)

  LEAK=""
  while IFS= read -r term || [[ -n "$term" ]]; do
    case "$term" in ''|'#'*) continue ;; esac
    # -F: термин — строка, не регекс. -i: регистр не спасает от утечки. -l: только имена.
    HITS="$(git ls-files -z 2>/dev/null | xargs -0 grep -ilF -- "$term" 2>/dev/null || true)"
    [[ -n "$HITS" ]] && LEAK="${LEAK}$(printf '%s' "$HITS" | tr '\n' ' ')"
  done < "$PRIV"
  check "внутренних имён в трекаемых файлах нет" "" "$LEAK"
  [[ "$GONE" -gt 0 ]] && printf '       %s\n' \
    "не прочитано: ${GONE} записей индекса без файла на диске (удалено/перенесено до коммита) — в HEAD они пока есть"
fi

# 23. У каждой ссылки из языкового правила на `.claude/docs/<имя>.md` есть источник: либо
# core-шаблон, либо шаблон в lang-pack. Проверка 10 требует «доставляется ИЛИ помечена условной»
# и потому пропускает случай, где оговорка на месте, а источник переименовали или удалили.
# Дефект был именно в паре: инструкция наложения копировала `*.template` без снятия суффикса, и
# в инстансе лежал `design-conformance.md.template` под ссылкой на `design-conformance.md`.
NOSRC=""
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  FOUND=no
  [[ -f "skeleton/.claude/docs/${name}.md.template" ]] && FOUND=yes
  for lp in skeleton/lang-packs/*/docs/"${name}.md.template"; do
    [[ -f "$lp" ]] && FOUND=yes
  done
  [[ "$FOUND" == yes ]] || NOSRC="${NOSRC}${name} "
done < <(grep -oh '\.claude/docs/[A-Za-z0-9_-]\+\.md' skeleton/.claude/rules/lang/*.md 2>/dev/null \
           | sed 's|.*/||; s|\.md$||' | sort -u)
check "у ссылок языковых правил на доки есть шаблон-источник" "" "$NOSRC"

# 24. Догфуд-копии в `.claude/` этой репы не расходятся со `skeleton/`.
# Оба набора скилов видны в сессии одновременно (`plan` и `skeleton:plan`), поэтому расхождение
# означает, что над шаблоном работают по ОСЛАБЛЕННОЙ версии того, что шаблон проповедует.
# Так и было: догфуд-`append.sh` гасил пустую заметку через `${NOTE// }` (только пробелы), а
# skeleton — через `[[:space:]]*` (и табы); догфуд-`plan` отстал на две секции. Собственный
# принцип «одна причина — одно место» на своей же репе не соблюдался (ревью 14.08).
DOGDRIFT=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  TWIN="skeleton/${f}"
  [[ -f "$TWIN" ]] || continue        # своё, без близнеца в скелете — законно
  [[ "$(md5 -q "$f" 2>/dev/null)" == "$(md5 -q "$TWIN" 2>/dev/null)" ]] \
    || DOGDRIFT="${DOGDRIFT}${f} "
done < <(git ls-files '.claude/*' 2>/dev/null)
check "догфуд-копии в .claude совпадают со skeleton" "" "$DOGDRIFT"

# 25. Каждая ссылка `ADR-N` из кода и доков резолвится в реестре `docs/decisions.md`.
# Проверка была описана в шапке реестра КОМАНДОЙ для ручного прогона — то есть существовала
# как документация. Ровно этим она однажды и вскрыла ADR-13: на номер ссылались шесть мест,
# записи не было ни одной. Ручной прогон повторяется, пока про него помнят.
#
# Сам реестр из источника ссылок исключён намеренно: его проза перечисляет НОМЕРА ЧУЖОГО дома
# («здесь ADR-4, в вике — вика-ADR-11»), и они по определению не резолвятся здесь. Явная форма
# `вика-ADR-N` отсекается отдельно — это ссылка на другой дом, а не на этот реестр.
ADRDANGLE="$(python3 - <<'PY'
import re, subprocess, os
files = [f for f in subprocess.run(['git','ls-files','-z'], capture_output=True, text=True)
         .stdout.split('\0') if f]
reg = 'docs/decisions.md'
known = set()
if os.path.isfile(reg):
    known = set(re.findall(r'^## (ADR-\d+)', open(reg, encoding='utf-8').read(), re.M))
ref = re.compile(r'(вика-)?\b(ADR-\d+)')
bad = {}
for f in files:
    if f == reg or f.startswith(('reports/', 'docs/plans/')):
        continue
    if not f.endswith(('.md', '.sh', '.yml', '.yaml', '.txt')):
        continue
    try:
        lines = open(f, encoding='utf-8').read().splitlines()
    except Exception:
        continue
    for i, line in enumerate(lines, 1):
        for wiki, num in ref.findall(line):
            if wiki or num in known:
                continue
            bad.setdefault(num, []).append(f'{f}:{i}')
print(' '.join(f'{n}({",".join(v[:2])})' for n, v in sorted(bad.items())), end='')
PY
)"
check "каждая ссылка ADR-N резолвится в реестре" "" "$ADRDANGLE"

# 26. Каждый доставляемый guard кем-то ВЫЗЫВАЕТСЯ. Дыра нашлась подъёмом block-large-edit.sh:
# файл доехал обоими каналами, прошёл чистоту CORE и смоук — и ни одна проверка не спросила,
# висит ли он на событии. Guard, который не подключён, неотличим от работающего: он молчит,
# а молчание guard'а — это его штатное поведение при успехе (mute the green).
#
# Два законных исключения, оба с механизмом вызова вне settings.json:
#   pre-push.sh       — зовёт git-хук, который ставит bootstrap;
#   run-pytest-hook.sh — bootstrap подставляет его ИМЯ вместо run-test-hook.sh при lang=python.
# Список исключений держим здесь, а не в скрипте-источнике: расширять его надо осознанно, и
# каждое добавление обязано назвать, кто вызывает файл.
GUARDDEAD="$(python3 - <<'PY'
import os, re
conf = 'scripts/lib/layers.sh'
settings = 'skeleton/.claude/settings.json.template'
# Страж, которого зовёт другой страж (диспетчер), подключён не хуже названного
# в настройках напрямую: иначе дочерние хуки роутера выглядят мёртвыми.
import glob as _glob
_peers = ''.join(open(f, encoding='utf-8').read() for f in _glob.glob('skeleton/.claude/guards/*.sh'))
boot = 'scripts/bootstrap.sh'
core = re.findall(r'"(\.claude/guards/[^"]+\.sh)"', open(conf, encoding='utf-8').read())
s = open(settings, encoding='utf-8').read() if os.path.isfile(settings) else ''
b = open(boot, encoding='utf-8').read() if os.path.isfile(boot) else ''
allowed = {'pre-push.sh', 'run-pytest-hook.sh'}
dead = []
for path in core:
    name = os.path.basename(path)
    if name in allowed:
        # исключение законно только пока его вызыватель существует
        if name == 'pre-push.sh' and 'pre-push' not in b:
            dead.append(f'{name}(bootstrap больше не ставит git-хук)')
        if name == 'run-pytest-hook.sh' and 'run-pytest-hook' not in b:
            dead.append(f'{name}(bootstrap больше не подставляет)')
        continue
    if name not in s and name not in _peers:
        dead.append(f'{name}(не подключён ни в settings, ни другим стражем)')
print(' '.join(dead), end='')
PY
)"
check "каждый CORE-guard вызывается" "" "$GUARDDEAD"

# N. Собственное число этого скрипта в доке. Числа verify-* сверяются прогоном (проверка 2), а
# своё сидело в TODO непроверенным — единственное число в доках, за которым ничего не стояло.
#
# Сверяем ЧИСЛО ПРОВЕРОК (`OK+FAIL+1`), не число зелёных. Первая версия брала `OK+1` — и любой
# одиночный настоящий дефект давал ВТОРОЙ, ложный FAIL: «ждали 16, получили 17», хотя 17 в доке
# верно. Читатель шёл править верное число (нашло независимое ревью 13.08). Число проверок от
# результатов не зависит, поэтому красное остаётся ровно одно — то, которое настоящее.
# `SKIPPED` входит в счёт наравне: число ПРОВЕРОК в скрипте не зависит от того, выполнима ли
# каждая в этой копии. Иначе число в доке пришлось бы держать разным для клона и рабочей копии.
if [[ -f "$TODO" ]]; then
  DOC_DR="$(grep -o 'check-docs-reality` [0-9]\+ проверок' "$TODO" | head -1 | grep -o '[0-9]\+' || true)"
  check "check-docs-reality: число проверок в доке = факту" "$((OK + FAIL + SKIPPED + 1))" "$DOC_DR"
else
  skip "check-docs-reality: число проверок в доке = факту" "нет $TODO (операционка вне git)"
fi

if [[ "$SKIPPED" -gt 0 ]]; then
  printf '\n%s ok / %s FAIL / %s пропущено (операционка вне git — это не дефект)\n' \
    "$OK" "$FAIL" "$SKIPPED"
else
  printf '\n%s ok / %s FAIL\n' "$OK" "$FAIL"
fi
[[ "$FAIL" -eq 0 ]] || exit 1
