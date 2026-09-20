#!/usr/bin/env bash
# Самопроверка bootstrap.sh. Прогон: bash scripts/verify-bootstrap.sh
# Разворачивает Python-инстанс во временной папке и проверяет по группам (число условий
# растёт с каждым заходом — считает сам прогон, тут его не дублируем):
#   разворот      — дорендер файлов харнесса, подмена сенсора, плейсхолдеры, smoke, время
#   лог           — log-append вставляет запись сверху и отказывается на пустом входе
#   сверка AC     — check-ac-refs: дыра ловится, ID вне секции не считается, маска не глобится
#   Ярус 3        — pre-push: секрет-скан до тестов, изоляция stdin, активация git-хука
#   SessionStart  — видит спеку, вика грузится из личного конфига вне репозитория
#   doc-каркас    — ARCHITECTURE/gotchas/REVIEW/model-policy, секции, маркеры незаполненного
#   лог и MOC     — docs/log.md, docs/MOC.md с КРУГАМИ чтения (не ярусами: шкалы разведены)
#   карта доков   — блок в CLAUDE.md, отсутствие @-импортов
#   сенсор в деле — сигнал на красном тесте, молчание на зелёном
#   смоук         — verify-harness доехал, зелёный в инстансе, код 3 в самом шаблоне
#   роли-агенты   — дефолт без них, флаг --agents доставляет
# Второй инстанс (lang=none) разворачивается только для проверки флага --agents.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

# Скрипт перезаписывает один и тот же .py дважды за секунду — ровно тот случай,
# где Python считает устаревший .pyc валидным (mtime совпал) и исполняет старый код.
export PYTHONDONTWRITEBYTECODE=1

check() {
  if [[ "$2" == "$3" ]]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1 — ожидалось [$3], получено [$2]"
    FAILED=1
  fi
}

# Правка конфига пробы: `sed -i` несовместим между платформами — BSD (macOS) требует аргумент
# суффикса (`sed -i ''`), GNU (Linux, а значит и любой CI-раннер) на этот же вызов падает
# с «invalid command code». Скрипт гоняется у владельца на macOS, поэтому дефект был невидим:
# первый прогон в Linux-CI или у контрибьютора уронил бы весь сьют на непонятной ошибке.
# Тот же урок уже записан в skeleton/scripts/log-append.sh — здесь он просто не был применён.
# Пишем через временный файл: работает одинаково везде и не зависит от диалекта -i.
conf_set() {
  local file="$1" expr="$2" tmp
  tmp="$(mktemp)"
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

P="$(mktemp -d)"
# Нормализация обязательна: mktemp отдаёт /var/..., а git rev-parse внутри той же
# папки вернёт /private/var/... (/var — симлинк на macOS). Хуки сравнивают пути
# строкой и молча вышли бы с нулём, показав «сенсор молчит» на исправном сенсоре.
P="$(cd "$P" && pwd -P)"
cd "$P" || exit 1

echo "== Разворот Python-инстанса =="
START=$(date +%s)
bash "$TPL/scripts/bootstrap.sh" probe python >/dev/null 2>&1
ELAPSED=$(( $(date +%s) - START ))

[[ -f "$P/CLAUDE.md" ]] && R=yes || R=no
check "CLAUDE.md дорендерен" "$R" yes

[[ -f "$P/.claude/settings.json" ]] && R=yes || R=no
check "settings.json дорендерен" "$R" yes

[[ -f "$P/.harness.conf" ]] && R=yes || R=no
check "harness.conf создан" "$R" yes

[[ -f "$P/docs/specs/_template.md" ]] && R=yes || R=no
check "шаблон спеки на месте" "$R" yes

[[ -f "$P/.claude/guards/run-pytest-hook.sh" ]] && R=yes || R=no
check "Python-сенсор приехал" "$R" yes

# Годится любой вариант: прямая подмена хука под стек ИЛИ диспетчер, который
# роутит по расширению и зовёт нужный дочерний хук сам.
grep -qE "run-pytest-hook\.sh|sensor\.sh" "$P/.claude/settings.json" 2>/dev/null && R=yes || R=no
check "Python-правки уходят в pytest (подменой или диспетчером)" "$R" yes

grep -q 'PYTEST_MODE="map"' "$P/.harness.conf" 2>/dev/null && R=yes || R=no
check "режим сенсора map" "$R" yes

if grep -q "<[A-Z_]\{2,\}>" "$P/CLAUDE.md" "$P/.claude/settings.json" 2>/dev/null; then R=есть; else R=нет; fi
check "незаменённых плейсхолдеров нет" "$R" нет

[[ -x "$P/scripts/load-context.sh" ]] && R=yes || R=no
check "SessionStart-скрипт существует и исполняем" "$R" yes

CTX_OUT=$(cd "$P" && bash scripts/load-context.sh 2>&1)
echo "$CTX_OUT" | grep -q "код не начинаем" && R=yes || R=no
check "SessionStart напоминает про spec-first" "$R" yes

# log-append.sh: правило в workflow.md и скил end-session требуют его ПО ИМЕНИ и
# запрещают Edit для лога. Проверяем не наличие, а работу — файл на месте, но не
# вставляющий запись, оставил бы правило неисполнимым при зелёной проверке.
[[ -x "$P/scripts/log-append.sh" ]] && R=yes || R=no
check "log-append.sh доставлен и исполняем" "$R" yes

LOG_BEFORE=$(wc -l < "$P/docs/log.md" 2>/dev/null | tr -d ' ')
printf '## 2026-01-01 — проверка доставки\n\nстрока из verify-bootstrap\n' > "$P/.probe-entry.md"
(cd "$P" && bash scripts/log-append.sh .probe-entry.md >/dev/null 2>&1) && R=yes || R=no
check "log-append вставляет запись" "$R" yes

LOG_AFTER=$(wc -l < "$P/docs/log.md" 2>/dev/null | tr -d ' ')
[[ "${LOG_AFTER:-0}" -gt "${LOG_BEFORE:-0}" ]] && R=yes || R=no
check "лог вырос после вставки" "$R" yes

# Запись обязана лечь ПЕРЕД старыми: лог читается сверху.
FIRST_HDR=$(grep -m1 '^## ' "$P/docs/log.md" 2>/dev/null)
[[ "$FIRST_HDR" == *"проверка доставки"* ]] && R=yes || R=no
check "новая запись легла сверху" "$R" yes

(cd "$P" && : > .empty-entry.md && bash scripts/log-append.sh .empty-entry.md >/dev/null 2>&1) && R=прошло || R=отказ
check "пустая запись отклонена" "$R" отказ

# --- Сверка AC ↔ тест -----------------------------------------------------------
# На шаблон спеки ссылается docs/specs/_template.md, поэтому скрипт обязан доехать.
[[ -x "$P/scripts/check-ac-refs.sh" ]] && R=yes || R=no
check "check-ac-refs.sh доставлен и исполняем" "$R" yes

[[ -f "$P/scripts/check-ac-refs.baseline" ]] && R=yes || R=no
check "baseline порога создан" "$R" yes

grep -q '^AC_TEST_GLOBS="[^"]\+"' "$P/.harness.conf" 2>/dev/null && R=yes || R=no
check "AC_TEST_GLOBS заполнен под стек" "$R" yes

# Свежий инстанс: спек нет → судить не о чем, обязан быть тихий успех.
(cd "$P" && bash scripts/check-ac-refs.sh --quiet >/dev/null 2>&1) && R=0 || R=не0
check "без спек проверка не падает" "$R" 0

# Спека с критерием, теста нет → обязан упасть. Это и есть та дыра, ради которой скрипт.
mkdir -p "$P/docs/specs"
printf '# Спека: проба\n\n## Verification (AC)\n\n- [ ] **AC-001** — критерий без теста\n' \
  > "$P/docs/specs/spec-probe.md"
(cd "$P" && bash scripts/check-ac-refs.sh --quiet >/dev/null 2>&1) && R=прошло || R=упало
check "AC без теста ловится" "$R" упало

# Ссылка из теста появилась → обязан пройти. Каталог и маску берём из .harness.conf,
# иначе проверка молча разошлась бы с тем, что реально настроено в инстансе.
AC_DIR_CONF=$(grep '^AC_TEST_DIR=' "$P/.harness.conf" | sed 's/^AC_TEST_DIR="//; s/"$//; s|\$REPO_ROOT|'"$P"'|')
AC_GLOB_ONE=$(grep '^AC_TEST_GLOBS=' "$P/.harness.conf" | sed 's/^AC_TEST_GLOBS="//; s/"$//' | awk '{print $1}')
mkdir -p "$AC_DIR_CONF"
AC_PROBE_FILE="$AC_DIR_CONF/${AC_GLOB_ONE//\*/ac_probe}"

# Регресс на глоббинг: без noglob маска схлопывается в имя файла из корня, find пуст,
# проверка уходит в fail-open. Кейс различающий: AC есть, теста нет → обязано УПАСТЬ.
DECOY="$P/${AC_GLOB_ONE//\*/decoy}"
: > "$DECOY"
(cd "$P" && bash scripts/check-ac-refs.sh --quiet >/dev/null 2>&1) && R=прошло || R=упало
check "маска не схлопывается в файл из корня" "$R" упало
rm -f "$DECOY"
# Контент — КОММЕНТАРИЙ: `#` валиден и в .py, и в .ts. Голый текст сделал бы файл
# несобираемым, и следующая проверка (smoke-тест инстанса) упала бы из-за этой пробы.
printf '# AC-001 — ссылка из теста для verify-bootstrap\n' > "$AC_PROBE_FILE"
(cd "$P" && bash scripts/check-ac-refs.sh --quiet >/dev/null 2>&1) && R=прошло || R=упало
check "AC со ссылкой из теста проходит" "$R" прошло

# ID вне секции Verification критерием не считается — иначе любое упоминание требовало теста.
# AC-777 кладём ИМЕННО ЧЕКБОКСОМ и в другую секцию: обычным текстом проверка декоративна —
# мутация показала, что на сломанном разборе секций она не краснеет (ID вне чекбокса
# не берётся и так).
printf '\n## Изменения\n\n- [ ] **AC-777** — пункт изменений, не критерий приёмки\n' \
  >> "$P/docs/specs/spec-probe.md"
(cd "$P" && bash scripts/check-ac-refs.sh --quiet >/dev/null 2>&1) && R=прошло || R=упало
check "ID вне секции Verification не считается" "$R" прошло

# Пробы намеренно ОСТАЮТСЯ до конца прогона, и это не небрежность:
#   `spec-probe.md` — фикстура для load-context («видит активную спеку»);
#   `$AC_PROBE_FILE` (ссылка на AC-001) — держит сверку AC зелёной, иначе она блокирует
#   Ярус 3 на каждом кейсе про скан, тесты и покрытие, и те проверяют не то, что заявлено.
# Кейс «дыра в покрытии AC» ссылку убирает сам и сам возвращает.
# Прежний комментарий здесь обещал уборку, но её не делал: обещание в тексте проверкой
# не является.

echo "== Ярус 3: gate + секрет-скан + сверка AC + тесты + покрытие =="

[[ -x "$P/.claude/guards/pre-push.sh" ]] && R=yes || R=no
check "pre-push.sh доставлен и исполняем" "$R" yes

# Активация. Логика в guards версионируется, а включает её git-хук — иначе Ярус 3
# существует только у того, кто скопировал .husky/pre-push руками.
[[ -x "$P/.git/hooks/pre-push" ]] && R=yes || R=no
check "git-хук pre-push активирован" "$R" yes

grep -q 'guards/pre-push.sh' "$P/.git/hooks/pre-push" 2>/dev/null && R=yes || R=no
check "хук зовёт guard, а не дублирует логику" "$R" yes

grep -q '^SECRET_SCAN_CMD=' "$P/.harness.conf" && R=yes || R=no
check "SECRET_SCAN_CMD в конфиге есть" "$R" yes

# Дальше проверяется САМ guard — порядок шагов и реакция на коды выхода. Реальные ruff и
# pytest тут только замедляют: четыре прогона по несколько минут, а при сломанном порядке
# (мутация) прогон вообще перестаёт заканчиваться. Подменяем на дешёвые, в конце возвращаем.
conf_set "$P/.harness.conf" 's|^GATE_CMD=.*|GATE_CMD="true"|'
# Тесты ЗЕЛЁНЫЕ и оставляют след. Падающие тесты делали проверку «падение скана блокирует»
# декоративной: ненулевой код давали они, и проверка показывала «блокирует» даже там, где
# секрет-скана в guard не было вовсе.
conf_set "$P/.harness.conf" 's|^GATE_TEST_CMD=.*|GATE_TEST_CMD="echo ТЕСТЫ-ПОШЛИ"|'

# `</dev/null` во всех прогонах ниже: gate.sh читает stdin до EOF, и с открытым stdin
# проверка висит вместо того, чтобы дать вердикт.

# Изоляция stdin. Git подаёт pre-push список ref'ов на stdin, а gate.sh читает stdin как
# контекст Stop-хука и при `stop_hook_active: true` выходит, НЕ прогнав гейт. Подаём именно
# такой JSON — гейт обязан отработать всё равно.
# Гейт делаем ПАДАЮЩИМ: при успехе он молчит (mute the green), и метка в выводе не появилась
# бы даже на исправном guard — проверка краснела бы всегда.
conf_set "$P/.harness.conf" 's|^GATE_CMD=.*|GATE_CMD="echo ГЕЙТ-ПОШЁЛ; false"|'
PP_OUT="$(printf '{"stop_hook_active": true}' | (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1)"
[[ "$PP_OUT" == *"ГЕЙТ-ПОШЁЛ"* ]] && R=yes || R=no
check "stdin вызывающего не утекает в gate" "$R" yes
conf_set "$P/.harness.conf" 's|^GATE_CMD=.*|GATE_CMD="true"|'

# Пустой SECRET_SCAN_CMD: push не блокируется, но и не молчит — иначе отсутствие скана
# неотличимо от пройденного.
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"SECRET_SCAN_CMD пуст"* ]] && R=yes || R=no
check "про отсутствие скана сказано вслух" "$R" yes

# Падение скана обязано остановить push. Тесты зелёные, поэтому ненулевой код может прийти
# только от скана.
conf_set "$P/.harness.conf" 's|^SECRET_SCAN_CMD=.*|SECRET_SCAN_CMD="false"|'
( (cd "$P" && sh .claude/guards/pre-push.sh) >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "падение скана блокирует push" "$R" упало

# Порядок: скан идёт ДО тестов. След тестов в выводе при падшем скане означает, что до них
# дошли — то есть порядок обратный.
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"ТЕСТЫ-ПОШЛИ"* ]] && R=после || R=не-дошло
check "скан отрабатывает до тестов" "$R" не-дошло

# Зелёный скан пропускает дальше.
conf_set "$P/.harness.conf" 's|^SECRET_SCAN_CMD=.*|SECRET_SCAN_CMD="true"|'
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"ТЕСТЫ-ПОШЛИ"* ]] && R=да || R=нет
check "зелёный скан пускает к тестам" "$R" да

# --- Сверка «критерий приёмки ↔ тест» на Ярусе 3 -----------------------------------
# Скрипт есть в CORE с 12.08, но не вызывался ниоткуда: проверка существовала и работала
# только руками. Здесь проверяется именно ВЫЗОВ, а не наличие файла.

# Дыра: AC-ID в спеке есть (`spec-probe.md` создан выше), файлы тестов по маске есть от
# bootstrap'а, а ссылку на ID убираем → push обязан встать. Своей спеки не заводим: вторая
# спека с тем же ID маскировала бы состояние первой.
rm -f "$AC_PROBE_FILE"
( (cd "$P" && sh .claude/guards/pre-push.sh) >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "AC без ссылки из теста блокирует push" "$R" упало

# Порядок: сверка идёт ДО полных тестов. След тестов в выводе означал бы обратный порядок,
# то есть дорогой шаг гоняется впустую перед дешёвым отказом.
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"ТЕСТЫ-ПОШЛИ"* ]] && R=после || R=не-дошло
check "сверка AC отрабатывает до тестов" "$R" не-дошло

# Ссылка из теста закрывает дыру — и прогон идёт дальше. Файл тот же, что выше по скрипту
# (`AC_PROBE_FILE`), чтобы кейс шёл на реальной маске инстанса, а не на придуманной.
printf '# AC-001 — ссылка из теста для Яруса 3\n' > "$AC_PROBE_FILE"
( (cd "$P" && sh .claude/guards/pre-push.sh) >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "ссылка на AC-ID из теста снимает блок" "$R" прошло

# Скрипта нет → сказано вслух. Молчаливый пропуск неотличим от пройденной сверки.
mv "$P/scripts/check-ac-refs.sh" "$P/scripts/check-ac-refs.sh.off"
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"check-ac-refs.sh нет"* ]] && R=сказал || R=молчит
check "про отсутствие сверки AC сказано вслух" "$R" сказал
mv "$P/scripts/check-ac-refs.sh.off" "$P/scripts/check-ac-refs.sh"

# Тот же дефект, увиденный РАНЬШЕ: gate на Stop обязан сказать про дыру и НЕ блокировать.
# Иначе о непокрытом критерии узнаёшь только на push, а между спекой и push помещается вся работа.
rm -f "$AC_PROBE_FILE"
G_OUT="$(printf '{}' | (cd "$P" && bash .claude/guards/gate.sh) 2>&1)"; G_CODE=$?
[[ "$G_OUT" == *"AC БЕЗ ТЕСТА"* ]] && R=сказал || R=молчит
check "gate на Stop предупреждает про AC без теста" "$R" сказал
[[ "$G_CODE" -eq 0 ]] && R=пустил || R=заблокировал
check "gate этим не блокирует ход" "$R" пустил

# Дубля быть не должно: pre-push зовёт gate шагом 1 и сам гоняет сверку шагом 3. Без stdin
# (то есть не как Stop-хук) gate про AC молчит.
G_OUT="$( (cd "$P" && bash .claude/guards/gate.sh </dev/null) 2>&1 )"
[[ "$G_OUT" == *"AC БЕЗ ТЕСТА"* ]] && R=дублирует || R=молчит
check "без stdin gate про AC молчит (нет дубля на push)" "$R" молчит

# Ссылку возвращаем: следующие кейсы Яруса 3 (пустой GATE_TEST_CMD, отсутствие чекера
# покрытия) должны доходить до своих шагов, а не спотыкаться о дыру в покрытии AC.
printf '# AC-001 — ссылка из теста для Яруса 3\n' > "$AC_PROBE_FILE"

# Конфиг возвращаем: дальше по нему проверяют сенсор, гейт и smoke.
conf_set "$P/.harness.conf" 's|^SECRET_SCAN_CMD=.*|SECRET_SCAN_CMD=""|'
conf_set "$P/.harness.conf" 's|^GATE_CMD=.*|GATE_CMD="uv run ruff check . \&\& uv run ruff format --check ."|'
conf_set "$P/.harness.conf" 's|^GATE_TEST_CMD=.*|GATE_TEST_CMD="uv run pytest"|'

echo "== Покрытие изменённых строк =="

[[ -x "$P/scripts/check-diff-coverage.sh" ]] && R=yes || R=no
check "check-diff-coverage доставлен и исполняем" "$R" yes

[[ -f "$P/scripts/check-diff-coverage.baseline" ]] && R=yes || R=no
check "порог покрытия создан" "$R" yes

# Ненастроенность (COVERAGE_REPORT пуст) — тихий успех: отчёт покрытия зависит от стека,
# честного дефолта нет. Но молчать нельзя, поэтому проверяем и текст предупреждения.
DC_OUT="$( (cd "$P" && bash scripts/check-diff-coverage.sh) 2>&1 </dev/null )"
DC_RC=$?
[[ $DC_RC -eq 0 ]] && R=0 || R="$DC_RC"
check "без COVERAGE_REPORT проверка не падает" "$R" 0

[[ "$DC_OUT" == *"COVERAGE_REPORT не задан"* ]] && R=сказал || R=промолчал
check "про ненастроенность покрытия сказано" "$R" сказал

# Настоящий кейс: изменённая непокрытая строка при пороге 100 обязана уронить прогон.
# Фикстура своя, чтобы не зависеть от стека инстанса.
DCF="$P/../dc-probe"; rm -rf "$DCF"; mkdir -p "$DCF/src" "$DCF/scripts"
cp "$P/scripts/check-diff-coverage.sh" "$DCF/scripts/"
(
  cd "$DCF" && git init -q . && git config user.email t@t && git config user.name t
  printf 'def a():\n    return 1\n' > src/m.py
  printf 'COVERAGE_REPORT="coverage.xml"\nDIFF_COVER_BASE="master"\n' > .harness.conf
  echo 100 > scripts/check-diff-coverage.baseline
  cat > coverage.xml <<'XML'
<?xml version="1.0"?>
<coverage><packages><package><classes>
<class filename="src/m.py"><lines>
<line number="1" hits="1"/><line number="2" hits="1"/><line number="4" hits="0"/>
</lines></class>
</classes></package></packages></coverage>
XML
  git add -A && git commit -qm base && git branch -M master
  git checkout -q -b feat
  printf 'def a():\n    return 1\n\ndef b():\n    return 2\n' > src/m.py
  git add -A && git commit -qm feat
  # Отчёт обязан быть СТРОГО новее изменённых файлов, иначе checker честно откажется судить по
  # устаревшему отчёту и выйдет нулём — а кейс ждёт красного. Без этого touch фикстура писала
  # файл и отчёт в одну секунду, и кто новее решала сортировка внутри секунды: один красный на
  # ~7 прогонов, причём КРАСНЫЙ на исправном коде. Поймано 14.08 подряд-прогонами.
  touch coverage.xml
) >/dev/null 2>&1
( cd "$DCF" && CLAUDE_PROJECT_DIR="$DCF" bash scripts/check-diff-coverage.sh --quiet >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "непокрытая изменённая строка роняет прогон" "$R" упало

# Рефакторинг покрытых строк при том же пороге 100 обязан пройти — это и есть причина, по
# которой считаем diff, а не пары «файл ↔ тест».
(
  cd "$DCF" && git checkout -q master && git checkout -q -b refactor
  printf 'def alpha():\n    return 1\n' > src/m.py
  git add -A && git commit -qm refactor
  # Здесь touch важнее, чем в кейсе выше: этот ждёт ЗЕЛЁНОГО, а отказ судить по устаревшему
  # отчёту тоже даёт код 0. Без touch кейс проходил бы иногда по верной причине, иногда потому,
  # что проверка вообще не состоялась, — и отличить нельзя.
  touch coverage.xml
) >/dev/null 2>&1
( cd "$DCF" && CLAUDE_PROJECT_DIR="$DCF" bash scripts/check-diff-coverage.sh --quiet >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "рефакторинг покрытых строк проходит при пороге 100" "$R" прошло

# Регресс на ложное совпадение путей (ревью 13.08): запись отчёта `src/m.py` подходит и
# `frontend/src/m.py`, и `backend/src/m.py`. Раньше строки судились по чужой таблице покрытия;
# теперь путь объявляется неоднозначным и не судится.
(
  cd "$DCF" && git checkout -q master
  mkdir -p frontend/src backend/src
  printf 'def a():\n    return 1\n' > frontend/src/m.py
  printf 'def a():\n    return 1\n' > backend/src/m.py
  git add -A && git commit -qm twins && git branch -f master HEAD
  git checkout -q -b ambig
  printf 'def a():\n    return 1\n\ndef b():\n    return 2\n' > frontend/src/m.py
  git add -A && git commit -qm ambig
  touch coverage.xml
) >/dev/null 2>&1
DC_OUT="$( (cd "$DCF" && CLAUDE_PROJECT_DIR="$DCF" bash scripts/check-diff-coverage.sh) 2>&1 </dev/null )"
[[ "$DC_OUT" == *"неоднозначный путь"* ]] && R=назвал || R=промолчал
check "одноимённые файлы: путь назван неоднозначным" "$R" назвал

# Регресс на юникод в имени: git цитирует такие пути в хедере diff, и файл выпадал из проверки.
(
  cd "$DCF" && git checkout -q master && git checkout -q -b uni
  printf 'def a():\n    return 1\n\ndef b():\n    return 2\n' > "frontend/src/тест.py"
  git add -A && git commit -qm uni
  cat > coverage.xml <<'XML'
<?xml version="1.0"?>
<coverage><packages><package><classes>
<class filename="frontend/src/тест.py"><lines>
<line number="1" hits="1"/><line number="2" hits="1"/><line number="4" hits="0"/>
</lines></class>
</classes></package></packages></coverage>
XML
  touch coverage.xml
) >/dev/null 2>&1
( cd "$DCF" && CLAUDE_PROJECT_DIR="$DCF" bash scripts/check-diff-coverage.sh --quiet >/dev/null 2>&1 </dev/null ) && R=прошло || R=упало
check "юникод в имени файла не выпадает из проверки" "$R" упало

# Регресс на устаревший отчёт: покрытие от прошлого прогона описывает код, которого уже нет.
(cd "$DCF" && touch -t 200001010000 coverage.xml) >/dev/null 2>&1
DC_OUT="$( (cd "$DCF" && CLAUDE_PROJECT_DIR="$DCF" bash scripts/check-diff-coverage.sh) 2>&1 </dev/null )"
[[ "$DC_OUT" == *"старее изменённых файлов"* ]] && R=назвал || R=промолчал
check "устаревший отчёт покрытия назван вслух" "$R" назвал

rm -rf "$DCF"

echo "== Чистота CORE (lint-core-purity) =="

# Фикстура своя: кейсы не должны зависеть от текущего состояния правил шаблона, иначе они
# начнут краснеть или зеленеть от любой правки текста, не относящейся к линту.
LCP="$P/../lcp-probe"; rm -rf "$LCP"; mkdir -p "$LCP/rules" "$LCP/scripts"
printf 'npm\nvitest\n' > "$LCP/scripts/deny.txt"
echo 0 > "$LCP/scripts/baseline"
lcp() {  # $1 — содержимое пробного правила; печатает «прошло» либо «упало»
  printf '%s\n' "$1" > "$LCP/rules/probe.md"
  ( CORE_DENYLIST="$LCP/scripts/deny.txt" \
    CORE_PURITY_BASELINE="$LCP/scripts/baseline" \
    CORE_PURITY_GLOBS="$LCP/rules/*.md" \
    bash "$TPL/scripts/lint-core-purity.sh" --quiet >/dev/null 2>&1 ) && echo прошло || echo упало
}

check "чистое правило проходит" "$(lcp '- Проверка закрывает изменение.')" прошло
check "стек-токен ловится" "$(lcp '- Гоняй `npm run build` перед пушем.')" упало
check "core-ok с причиной пропускает" \
  "$(lcp '- Гоняй `npm run build`. <!-- core-ok: пример команды, не правило -->')" прошло
# Метка без причины раньше проходила: glob-паттерн `[!-[:space:]]*` матчит пустой хвост.
check "core-ok без причины не пропускает" "$(lcp '- Гоняй `npm run build`. <!-- core-ok: -->')" упало
check "висячая ссылка Gotcha ловится" "$(lcp '- Правило без обоснования (Gotcha 56).')" упало
check "голая дата ловится" "$(lcp '- Правило, которое что-то доказало 29.07.')" упало

# Нет денилиста → судить не по чему: предупреждение и exit 0, а не красный на пустом месте.
LCP_OUT="$( CORE_DENYLIST="$LCP/scripts/нет.txt" CORE_PURITY_GLOBS="$LCP/rules/*.md" \
  bash "$TPL/scripts/lint-core-purity.sh" 2>&1 )" && R=0 || R=не0
check "без денилиста линт не падает" "$R" 0
[[ "$LCP_OUT" == *"нет файла денилиста"* ]] && R=сказал || R=молчит
check "про отсутствие денилиста сказано вслух" "$R" сказал

rm -rf "$LCP"

# Регресс: SessionStart не должен падать в среде без HOME. Раньше `${HOME}` внутри default-
# выражения разворачивался под set -u и ронял скрипт до его же graceful-ветки.
(cd "$P" && env -u HOME bash scripts/load-context.sh >/dev/null 2>&1) && R=0 || R=не0
check "load-context не падает без HOME" "$R" 0

# Регресс: пустой GATE_TEST_CMD молчал, хотя не запускавшиеся тесты неотличимы от прошедших.
conf_set "$P/.harness.conf" 's|^GATE_TEST_CMD=.*|GATE_TEST_CMD=""|'
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"GATE_TEST_CMD пуст"* ]] && R=сказал || R=промолчал
check "пустой GATE_TEST_CMD назван вслух" "$R" сказал

# Регресс: отсутствие check-diff-coverage.sh в инстансе тоже должно быть слышно.
mv "$P/scripts/check-diff-coverage.sh" "$P/scripts/.hidden-dc"
PP_OUT="$( (cd "$P" && sh .claude/guards/pre-push.sh) 2>&1 </dev/null )"
[[ "$PP_OUT" == *"check-diff-coverage.sh нет"* ]] && R=сказал || R=промолчал
check "отсутствие чекера покрытия названо вслух" "$R" сказал
mv "$P/scripts/.hidden-dc" "$P/scripts/check-diff-coverage.sh"
conf_set "$P/.harness.conf" 's|^GATE_TEST_CMD=.*|GATE_TEST_CMD="uv run pytest"|'

echo "== SessionStart: фаза работы и личный слой =="

[[ -x "$P/scripts/load-context.sh" ]] && R=yes || R=no
check "load-context.sh доставлен и исполняем" "$R" yes

# Вывод забираем в переменную, а не через `| grep -q`: grep закрывает пайп на первом
# совпадении, писатель получает SIGPIPE, и pipefail красит конвейер — проверка провалилась бы
# на исправном скрипте.
#
# Спека на месте (создана выше) — хук обязан её увидеть. Раньше корень считался как
# `dirname/../..`, уводил выше репо, и хук молча не находил ни спек, ни конфига.
LC_OUT="$(cd "$P" && bash scripts/load-context.sh 2>/dev/null)"
[[ "$LC_OUT" == *"spec-probe.md"* ]] && R=yes || R=no
check "видит активную спеку" "$R" yes

# Личный слой: адрес вики приходит ИЗ-ВНЕ репозитория, командный конфиг о нём не знает.
LOCAL_CONF="$P/../local-probe.conf"
mkdir -p "$P/../wiki-probe"
printf '# overview-проба\n' > "$P/../wiki-probe/overview.md"
printf 'WIKI_PATH="%s"\n' "$P/../wiki-probe" > "$LOCAL_CONF"
LC_OUT="$(cd "$P" && HARNESS_LOCAL_CONF="$LOCAL_CONF" bash scripts/load-context.sh 2>/dev/null)"
[[ "$LC_OUT" == *"overview-проба"* ]] && R=yes || R=no
check "вика грузится из личного конфига" "$R" yes

# Тот же прогон без личного конфига обязан молчать про вику, иначе слой не изолирован.
LC_OUT="$(cd "$P" && HARNESS_LOCAL_CONF="$P/../нет-такого.conf" bash scripts/load-context.sh 2>/dev/null)"
[[ "$LC_OUT" == *"Долгая память"* ]] && R=печатает || R=молчит
check "без личного конфига про вику молчит" "$R" молчит

grep -q '^WIKI_PATH=' "$P/.harness.conf" && R=есть || R=нет
check "WIKI_PATH не попал в командный конфиг" "$R" нет

rm -rf "$LOCAL_CONF" "$P/../wiki-probe"
rm -f "$AC_PROBE_FILE" "$P/docs/specs/spec-probe.md"

(cd "$P" && uv run pytest -q >/dev/null 2>&1) && R=green || R=red
check "smoke-тест зелёный" "$R" green

[[ $ELAPSED -lt 20 ]] && R=fast || R=slow
check "разворот меньше 20 с (факт: ${ELAPSED}с)" "$R" fast

echo "== Doc-каркас =="
for DOC in ARCHITECTURE gotchas REVIEW model-policy dor-gate completion background-offload testing-guide; do
  [[ -f "$P/.claude/docs/$DOC.md" ]] && R=yes || R=no
  check "$DOC.md дорендерен" "$R" yes
done

if grep -q "<[A-Z_]\{2,\}>\|{{[A-Z_]*}}" "$P/.claude/docs/"*.md 2>/dev/null; then R=есть; else R=нет; fi
check "плейсхолдеров в doc-каркасе нет" "$R" нет

grep -q "заполнить при скрининге" "$P/.claude/docs/ARCHITECTURE.md" 2>/dev/null && R=yes || R=no
check "незаполненное помечено маркером" "$R" yes

# AC-протокол ревью: словарь вердиктов и запрет ставить MET по наличию ссылки. Ссылку и так
# проверяет check-ac-refs грепом — от ревью нужен разбор поведения.
grep -q 'CANNOT ASSESS' "$P/.claude/docs/REVIEW.md" 2>/dev/null && R=да || R=нет
check "REVIEW несёт вердикты AC-сверки" "$R" да

grep -q 'AC-сверка недоступна' "$P/.claude/docs/REVIEW.md" 2>/dev/null && R=да || R=нет
check "случай «спеки нет» описан" "$R" да

# Доки, на которые CORE-правила ссылаются БЕЗУСЛОВНО, обязаны нести суть, а не заголовки:
# существование файла ничего не доказывает — пустой шаблон прошёл бы проверку на -f.
grep -q 'получено' "$P/.claude/docs/dor-gate.md" 2>/dev/null && R=да || R=нет
check "dor-gate несёт три ответа по входам" "$R" да

grep -q 'На доверии' "$P/.claude/docs/completion.md" 2>/dev/null && R=да || R=нет
check "completion делит понимание и доверие" "$R" да

grep -q 'Мутация' "$P/.claude/docs/testing-guide.md" 2>/dev/null && R=да || R=нет
check "testing-guide несёт процедуру мутации" "$R" да

grep -q 'Отдавать' "$P/.claude/docs/background-offload.md" 2>/dev/null && R=да || R=нет
check "background-offload несёт признак делегирования" "$R" да

# Ссылки CORE-правил на эти доки больше НЕ условные — значит битых быть не должно.
MISS=""
for D in dor-gate completion background-offload testing-guide model-policy; do
  [[ -f "$P/.claude/docs/$D.md" ]] || MISS="$MISS $D"
done
[[ -z "$MISS" ]] && R=все || R="нет:$MISS"
check "все доки из безусловных ссылок на месте" "$R" все

# На model-policy ссылается workflow.md как на существующий док, без оговорки «если завёл».
# Проверяем содержимое, а не факт файла: пустой док прошёл бы проверку на существование.
grep -q 'Fallback' "$P/.claude/docs/model-policy.md" 2>/dev/null && R=да || R=нет
check "model-policy содержит правило fallback" "$R" да

grep -q 'model-policy.md' "$P/docs/MOC.md" 2>/dev/null && R=да || R=нет
check "model-policy указан в MOC" "$R" да

grep -q "pytest" "$P/.claude/docs/ARCHITECTURE.md" 2>/dev/null && R=yes || R=no
check "языковые значения подставлены (pytest)" "$R" yes

grep -q "^## Модель данных" "$P/.claude/docs/ARCHITECTURE.md" 2>/dev/null && R=yes || R=no
check "секция «Модель данных» есть" "$R" yes

grep -q "^## Бизнес-логика" "$P/.claude/docs/ARCHITECTURE.md" 2>/dev/null && R=yes || R=no
check "секция «Бизнес-логика» есть" "$R" yes

# Внутри дерева структуры длинный маркер читается как мусор ("— заполнить.../ ← ...").
# В code-блоке нужен короткий; найдено прогоном 30.07.
grep -q "TODO/ *←" "$P/.claude/docs/ARCHITECTURE.md" 2>/dev/null && R=yes || R=no
check "в дереве структуры короткий маркер" "$R" yes

[[ -f "$P/docs/log.md" ]] && R=yes || R=no
check "docs/log.md создан" "$R" yes

[[ -f "$P/docs/MOC.md" ]] && R=yes || R=no
check "docs/MOC.md создан" "$R" yes

grep -q "Круг 0" "$P/docs/MOC.md" 2>/dev/null && R=yes || R=no
check "MOC размечен кругами чтения" "$R" yes

# Коллизия шкал. «Ярус» в этом харнессе означает ступень проверки (0 pre-commit … 3 pre-push),
# и до 13.08 MOC теми же словами нумеровал порядок чтения: у потребителя в одном проекте жили
# «ярус 0 = начни отсюда» и «ярус 0 = линт на коммите». Заголовки MOC обязаны быть кругами.
grep -qE '^## Ярус [0-9]' "$P/docs/MOC.md" 2>/dev/null && R=есть || R=нет
check "в MOC нет заголовков-ярусов (шкалы не путаются)" "$R" нет

# Разведение шкал названо вслух, а не только переименовано: без строки-оговорки читатель,
# знающий про ярусы проверки, всё равно спросит «а это те же?».
grep -q "ярусы 0–3 это ступени" "$P/docs/MOC.md" 2>/dev/null && R=yes || R=no
check "MOC отделяет круги чтения от ярусов проверки" "$R" yes

grep -q "Проектная документация" "$P/CLAUDE.md" 2>/dev/null && R=yes || R=no
check "карта доков в CLAUDE.md есть" "$R" yes

# @-импорт ДОКОВ затянул бы каркас в контекст на старте каждой сессии. Страховка от регресса.
#
# Блоки кода исключаются, и это не поблажка: парсер импортов Claude Code сам пропускает code
# spans и fenced-блоки (официальная дока, memory). Проверка, краснеющая на ПРИМЕРЕ внутри блока
# кода, строже реальности — то есть ложный красный, а его обходят вместе с проверкой. Поймано
# 14.08 на примере совместимости с AGENTS.md, который шаблон показывает как рекомендованный.
IMPORTS="$(CLAUDE_MD="$P/CLAUDE.md" python3 -c '
import os, re
fence = chr(96) * 3
try:
    lines = open(os.environ["CLAUDE_MD"], encoding="utf-8").read().splitlines()
except OSError:
    print(""); raise SystemExit
inside, bad = False, []
for i, line in enumerate(lines, 1):
    if line.lstrip().startswith(fence):
        inside = not inside
        continue
    if inside:
        continue
    if re.search(r"(^|\s)@(\.claude/)?docs/", line) or re.match(r"^@", line):
        bad.append(str(i))
print(" ".join(bad))
')"
[[ -z "$IMPORTS" ]] && R=нет || R="есть (строки: $IMPORTS)"
check "@-импортов доков в CLAUDE.md нет (примеры в блоках кода не считаются)" "$R" нет

echo "== Сенсор в деле =="
mkdir -p "$P/src/probe" "$P/tests"
cat > "$P/src/probe/calc.py" <<'PY'
def add(a: int, b: int) -> int:
    return a - b
PY
cat > "$P/tests/test_calc.py" <<'PY'
from probe.calc import add


def test_add() -> None:
    assert add(2, 2) == 4
PY

HOOK_JSON='{"tool_input":{"file_path":"'"$P"'/src/probe/calc.py"}}'

set +e
OUT=$(cd "$P" && echo "$HOOK_JSON" | bash "$P/.claude/guards/run-pytest-hook.sh" 2>/dev/null)
CODE=$?
set -e
[[ $CODE -eq 1 ]] && R=cried || R=silent
check "сенсор сигналит на красном тесте" "$R" cried

echo "$OUT" | grep -q additionalContext && R=yes || R=no
check "в выводе есть additionalContext" "$R" yes

cat > "$P/src/probe/calc.py" <<'PY'
def add(a: int, b: int) -> int:
    return a + b
PY
set +e
OUT=$(cd "$P" && echo "$HOOK_JSON" | bash "$P/.claude/guards/run-pytest-hook.sh" 2>/dev/null)
CODE=$?
set -e
[[ $CODE -eq 0 && -z "$OUT" ]] && R=silent || R=noisy
check "молчит при зелёном (mute the green)" "$R" silent

echo "== .NET-инстанс =="

# SDK у .NET-ветки намеренно не требуется: она кладёт каркас, solution заводит владелец.
# Ветка, которую нельзя развернуть на машине без dotnet, была бы непроверяемой.
PD="$(mktemp -d)"; PD="$(cd "$PD" && pwd -P)"
(cd "$PD" && bash "$TPL/scripts/bootstrap.sh" probe dotnet >/dev/null 2>&1) && R=0 || R=не0
check "разворот без установленного SDK" "$R" 0

grep -q '^READONLY_ZONES=".*obj' "$PD/.harness.conf" 2>/dev/null && R=да || R=нет
check "зоны .NET в конфиге (obj/artifacts)" "$R" да

grep -q '^AC_TEST_GLOBS=".*Tests\.cs' "$PD/.harness.conf" 2>/dev/null && R=да || R=нет
check "маски тестов .NET, не JS" "$R" да

# Конфиг обещает «настройки под твой стек» — python-строки в .NET-инстансе это обещание ломают.
grep -qE '^PYTEST_MODE|PYTHONDONTWRITEBYTECODE' "$PD/.harness.conf" && R=есть || R=нет
check "python-строк в конфиге .NET-инстанса нет" "$R" нет

# Ожидаем ДВА файла: свой язык плюс shell.md. Второй — CORE и едет всегда, потому что
# guard-хуки .NET-инстанса всё равно на shell. Сортировка нужна: порядок ls не гарантирован.
LANG_FILES="$(ls "$PD/.claude/rules/lang/" 2>/dev/null | sort | tr '\n' ' ')"
[[ "$LANG_FILES" == "dotnet.md shell.md " ]] && R=свой-и-shell || R="$LANG_FILES"
check "приехали dotnet.md и shell.md, больше ничего" "$R" свой-и-shell

# Пустой TEST_CMD у .NET законен. Сенсор обязан выйти, НЕ исполняя команду.
# Проверка статическая и это не лень: успешная команда всё равно глушится mute-the-green,
# поэтому по выводу два поведения неразличимы — мутация это показала.
mkdir -p "$PD/src"; echo 'class X {}' > "$PD/src/X.cs"
SENS_OUT="$(cd "$PD" && printf '{"tool_input":{"file_path":"%s/src/X.cs"}}' "$PD" | bash .claude/guards/run-test-hook.sh 2>&1)"
[[ -z "$SENS_OUT" ]] && R=молчит || R="шумит: $SENS_OUT"
check "сенсор молчит при пустом TEST_CMD" "$R" молчит

grep -q 'z "${TEST_CMD:-}" \]\] && exit 0' "$PD/.claude/guards/run-test-hook.sh" && R=есть || R=нет
check "ранний выход при пустом TEST_CMD в коде сенсора" "$R" есть

# А вот пустой гейт молчать не должен: это не «нет пофайлового прогона», это «Ярус 2 выключен».
GATE_OUT="$(cd "$PD" && bash .claude/guards/gate.sh </dev/null 2>&1)"
[[ "$GATE_OUT" == *"GATE_CMD в .harness.conf пуст"* ]] && R=сказал || R=промолчал
check "пустой гейт назван вслух" "$R" сказал

rm -rf "$PD"

echo "== Адрес шаблона в инстансе =="
# copier пишет `_src_path` тем путём, которым его позвали, а bootstrap зовёт локальным
# абсолютным. Инстанс с таким значением синкается только на машине раскатчика, и путь с той
# машины (имя пользователя, организации) уезжает в чужой проект. Ловим ровно это.
SRC="$(grep '^_src_path:' "$P/.copier-answers.yml" 2>/dev/null | sed 's/^_src_path:[[:space:]]*//')"
case "$SRC" in
  /*) R=путь-с-машины ;;
  '') R=строки-нет ;;
  *)  R=адрес ;;
esac
check "_src_path — адрес шаблона, не путь с машины раскатчика" "$R" адрес

echo "== Смоук харнесса в инстансе =="
# verify-harness.sh раньше лежал в scripts/ репы-шаблона и туда же смотрел за
# skeleton/.claude — то есть в любом инстансе краснел, а в самом шаблоне падал на
# отсутствующем .harness.conf. Теперь он CORE и доезжает вместе с харнессом.
[[ -x "$P/scripts/verify-harness.sh" ]] && R=yes || R=no
check "verify-harness.sh доставлен и исполняем" "$R" yes

set +e
VH_OUT="$(cd "$P" && bash scripts/verify-harness.sh 2>&1)"
VH_CODE=$?
set -e
check "смоук в свежем инстансе зелёный" "$VH_CODE" 0
[[ "$VH_OUT" == *"0 fail"* ]] && R=да || R=нет
check "ни одного FAIL в смоуке" "$R" да
# Пять проверок ниже — те, из-за которых смоук вообще существует. Зелёный итог без них
# был бы зелёным и на пустом прогоне.
for NEED in "guard блокирует readonly зону" "guard пропускает разрешённый путь" \
            "run-test-hook.sh исполняем" "защита от петли держит" "append.sh исполняем"; do
  [[ "$VH_OUT" == *"$NEED"* ]] && R=есть || R=нет
  check "смоук проверяет: ${NEED}" "$R" есть
done

# Запуск в самом шаблоне: не зелёный (проверять нечего) и не красный (кривой запуск
# ≠ поломанный харнесс). Отдельный код 3 — иначе шаблон вечно «красный» на своей проверке.
set +e
TPL_OUT="$(bash "$TPL/skeleton/scripts/verify-harness.sh" 2>&1)"
TPL_CODE=$?
set -e
check "в шаблоне смоук отвечает кодом 3" "$TPL_CODE" 3
[[ "$TPL_OUT" == *"Ничего не проверено"* ]] && R=сказал || R=промолчал
check "и говорит, что ничего не проверено" "$R" сказал

echo "== Роли-агенты по флагу =="
[[ -d "$P/.claude/agents" ]] && R=есть || R=нет
check "без флага папки agents нет" "$R" нет

PA="$(mktemp -d)"; PA="$(cd "$PA" && pwd -P)"
(cd "$PA" && bash "$TPL/scripts/bootstrap.sh" probe none --agents >/dev/null 2>&1)
# `|| true` обязателен: блок сенсора выше оставляет set -e включённым, а ls по
# отсутствующей папке (или grep без совпадений) убил бы скрипт до печати итога.
# Найдено прогоном 30.07 — обрыв вывода без единого FAIL.
AGENT_COUNT=$(ls -1 "$PA/.claude/agents/" 2>/dev/null | grep -c '\.md$' || true)
# 14.08 из боевого инстанса поднято четыре: `challenger` (adversarial-проверка находок) и три
# роли доменного ревью — `arbiter`, `lens-contracts`, `lens-tests`. Линза состояния в ядро НЕ
# пошла: её предмет привязан к UI-стеку, она уехала в lang-pack vue.
# Раньше ассерт ждал ТРИ и объяснял число ролями — третьим файлом был README пакета, который
# глоб затаскивал в рантайм-каталог. Тест закреплял дефект: починишь bootstrap — покраснеет
# на правильном поведении (ревью 14.08).
check "с флагом --agents приехало 6 файлов ролей" "$AGENT_COUNT" 6

# Считать файлы мало: дефект был именно в ПРИРОДЕ файла, а не в их числе. Определение субагента
# начинается с YAML-фронтматтера; всё остальное в этой папке — мусор для рантайма.
NO_FM=""
for AF in "$PA/.claude/agents/"*.md; do
  [[ -f "$AF" ]] || continue
  [[ "$(head -1 "$AF")" == "---" ]] || NO_FM="${NO_FM}$(basename "$AF") "
done
check "в agents нет файлов без фронтматтера" "$NO_FM" ""

# Уникальные роли на месте, core-ролей тут быть НЕ должно: их канон в плагине (ADR-14).
MISSING_ROLE=""
for role in bug-triage Explore challenger arbiter lens-contracts lens-tests; do
  [[ -f "$PA/.claude/agents/${role}.md" ]] || MISSING_ROLE="$MISSING_ROLE $role"
done
check "уникальные роли на месте (шесть, без плагинных)" "$MISSING_ROLE" ""

ls "$PA/.claude/agents/" 2>/dev/null | grep -qE '^(reviewer|scout|researcher|scribe)\.md$' && R=есть || R=нет
check "дублей core-ролей в инстансе нет" "$R" нет

# Explore переопределяет встроенный агент ради haiku — без этой строки смысл файла теряется.
grep -q 'model: haiku' "$PA/.claude/agents/Explore.md" 2>/dev/null && R=да || R=нет
check "Explore держит модель haiku" "$R" да

echo "== Гард на непустую папку =="
PB="$(mktemp -d)"; PB="$(cd "$PB" && pwd -P)"
touch "$PB/уже-есть.txt"
set +e
(cd "$PB" && bash "$TPL/scripts/bootstrap.sh" probe none >/dev/null 2>&1)
GUARD_CODE=$?
set -e
[[ $GUARD_CODE -ne 0 ]] && R=отказал || R=развернул
check "в непустой папке bootstrap отказывается" "$R" отказал

[[ -e "$PB/CLAUDE.md" || -e "$PB/.git" ]] && R=создал || R=нет
check "при отказе ничего не создано" "$R" нет

echo
echo "Инстанс: $P"
[[ $FAILED -eq 0 ]] && echo "ВСЁ ЗЕЛЁНОЕ" || echo "ЕСТЬ ПРОВАЛЫ"
exit $FAILED
