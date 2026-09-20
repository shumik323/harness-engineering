#!/usr/bin/env bash
# Разворот проекта с харнессом одной командой.
# Прогон из целевой ПУСТОЙ папки:
#   bash /path/to/harness-template/scripts/bootstrap.sh <имя> [lang]
# lang: python | vue | go | php | dotnet | none (по умолчанию python)
#
# Что делает: создаёт проект → зовёт copier с нужным языковым паком →
# дорендеривает CLAUDE.md / settings.json / .harness.conf (copier их не привозит,
# в скелете они лежат как .template/.example) → подменяет сенсор по языку → smoke.
set -euo pipefail

NAME="${1:?нужно имя проекта: bootstrap.sh <имя> [lang] [--agents]}"
LANG_PACK="${2:-python}"
# ADR-13: роли-агенты instance-owned, авто-доставки нет. Флаг = явное принятие.
WITH_AGENTS=no
[[ "${3:-}" == "--agents" ]] && WITH_AGENTS=yes

# Гард на непустую папку. Требование «запускать из пустой папки» стояло только
# комментарием в шапке, а uv init / git init / copier молча работают в любой — и разворот
# уехал в корень рабочего каталога со всеми проектами: git init там сломал определение
# границ репозитория для всех хуков (инцидент 30.07). .DS_Store игнорируем, его создаёт macOS.
EXISTING="$(ls -A 2>/dev/null | grep -v '^\.DS_Store$' || true)"
if [[ -n "$EXISTING" ]]; then
  {
    echo "Отказ: папка $(pwd) не пуста."
    echo "Найдено: $(echo "$EXISTING" | head -3 | tr '\n' ' ')"
    echo
    echo "Bootstrap разворачивает проект в ТЕКУЩУЮ папку. Создай пустую и зайди в неё:"
    echo "  mkdir -p $NAME && cd $NAME && bash $0 $NAME $LANG_PACK"
  } >&2
  exit 1
fi
TPL="$(cd "$(dirname "$0")/.." && pwd)"

case "$LANG_PACK" in
  python)
    command -v uv >/dev/null || { echo "нужен uv: https://docs.astral.sh/uv/" >&2; exit 1; }
    uv init --package --name "$NAME" . >/dev/null
    uv add --dev pytest ruff >/dev/null
    WATCH_DIR="src"
    TEST_CMD="uv run pytest -q"
    SENSOR="run-pytest-hook.sh"
    READONLY="__pycache__ .pytest_cache .ruff_cache .venv"
    GATE_CMD="uv run ruff check . && uv run ruff format --check ."
    GATE_TEST_CMD="uv run pytest"
    PKG_PATH="src/$NAME"
    LANG_VER="Python 3.12+ (uv-managed)"
    BUILD_TOOL="uv"
    TEST_FW="pytest"
    OTHER_TOOLS="ruff (lint + format)"
    AC_GLOBS="test_*.py *_test.py"
    # Тесты у python-инстанса лежат в tests/, а не в WATCH_DIR — искать ссылки надо там.
    AC_DIR="tests"
    ;;
  dotnet)
    # SDK намеренно НЕ требуется: bootstrap кладёт каркас харнесса, а solution заводит владелец
    # (`dotnet new sln` / `dotnet new webapi`). Требовать dotnet значило бы держать в шаблоне
    # непроверяемую ветку — SDK есть далеко не на каждой машине, где правят шаблон.
    git init -q .
    WATCH_DIR="src"
    # Пофайлового прогона в .NET нет: у `dotnet test` нет аналога "related tests". Сенсор
    # молчит, тесты закрывает Ярус 3.
    TEST_CMD=""
    SENSOR="run-test-hook.sh"
    READONLY="bin obj artifacts TestResults publish"
    # Гейт и тесты пустые ОСОЗНАННО: команда требует пути к solution, которого на свежем
    # инстансе нет. Строка с `App.sln` давала бы красный гейт на пустом месте. Пустой GATE_CMD
    # при существующем конфиге gate называет вслух — ложного зелёного не будет.
    GATE_CMD=""
    GATE_TEST_CMD=""
    PKG_PATH="src"
    LANG_VER=".NET 9/10 · ASP.NET Core Web API"
    BUILD_TOOL="dotnet"
    TEST_FW="xunit / Microsoft.Testing.Platform"
    OTHER_TOOLS="анализаторы SDK (CA/IDE), EnforceCodeStyleInBuild"
    AC_GLOBS="*Tests.cs *Test.cs"
    AC_DIR="tests"
    ;;
  vue|react|go|php|none)
    git init -q .
    WATCH_DIR="src"
    TEST_CMD="npx vitest related --run"
    SENSOR="run-test-hook.sh"
    READONLY="dist"
    GATE_CMD="npm run type-check && npm run lint"
    GATE_TEST_CMD="npm test"
    PKG_PATH="src"
    LANG_VER="TypeScript / Node"
    BUILD_TOOL="npm"
    TEST_FW="vitest"
    OTHER_TOOLS="eslint"
    # Оба расширения: часть тестов лежит в .tsx, и маска только по .ts молча теряла бы их.
    AC_GLOBS="*.test.ts *.test.tsx *.spec.ts"
    # У JS-стека тесты лежат рядом с кодом, поэтому каталог тот же, что WATCH_DIR.
    AC_DIR="src"
    ;;
  *)
    echo "неизвестный lang: $LANG_PACK (python|vue|react|go|php|dotnet|none)" >&2
    exit 1
    ;;
esac

# go/php делят ветку с vue (своих паков нет), но маски тестов нужны свои: JS-маски дают ноль
# файлов, и сверка AC уходит в fail-open при «заполненном» конфиге.
case "$LANG_PACK" in
  go)  AC_GLOBS="*_test.go";  AC_DIR="" ;;   # тесты рядом с кодом по всему модулю
  php) AC_GLOBS="*Test.php";  AC_DIR="tests" ;;
esac

# Поля, которые до постановки задачи неизвестны, получают честный маркер, а не
# остаются голым плейсхолдером: незаполненное должно читаться как незаполненное.
TODO_MARK="— заполнить при скрининге"
# Внутри code-блока с деревом структуры длинный маркер превращается в мусор
# ("— заполнить при скрининге/     ← основная единица"). Там нужен короткий.
TODO_SHORT="TODO"

# Python-специфичные строки конфига. Для остальных языков блок пуст: PYTEST_MODE читает
# только run-pytest-hook.sh, а PYTHONDONTWRITEBYTECODE нужен ровно pytest.
PY_CONF_BLOCK=""
if [[ "$LANG_PACK" == python ]]; then
  PY_CONF_BLOCK='PYTEST_MODE="map"
# Байткод-кэш Python сверяется по mtime с точностью до секунды. Агент правит файл
# чаще — вторая правка в ту же секунду оставляет .pyc «актуальным», и тест исполняет
# прошлую версию кода. Сенсор отдаёт ложный сигнал. Хук делает source этого файла,
# поэтому переменная доезжает до дочернего pytest. Найдено прогоном 29.07.
export PYTHONDONTWRITEBYTECODE=1'
fi

command -v copier >/dev/null || { echo "нужен copier: uv tool install copier" >&2; exit 1; }

# --vcs-ref HEAD обязателен. Без него copier для git-шаблона берёт последний ТЕГ
# (сейчас v0.1.8 от 23.06), а не рабочую копию — новые файлы скелета в инстанс
# не попадают и отсутствуют молча. Флот раскатывается с тега осознанно; локальная
# разработка кита должна видеть текущее состояние. Найдено прогоном 29.07.
copier copy --trust --defaults --overwrite --vcs-ref HEAD \
  --data project_name="$NAME" --data lang="$LANG_PACK" "$TPL" . >/dev/null

# `_src_path` copier записывает тем путём, которым его позвали, а зовём мы локальным
# абсолютным. Два следствия, и первое хуже: `copier update` в этом инстансе работает только
# там, где существует ровно этот каталог — то есть у всех, кроме раскатывавшего, синк мёртв.
# Второе: путь с чужой машины (а с ним имя пользователя и организации) уезжает в проект.
# Есть remote у шаблона — подставляем URL, он валиден для всех.
TPL_REMOTE="$(git -C "$TPL" config --get remote.origin.url 2>/dev/null || true)"
if [[ -n "$TPL_REMOTE" && -f .copier-answers.yml ]]; then
  TPL_REMOTE="$TPL_REMOTE" python3 - <<'PY'
import os, re
url = os.environ["TPL_REMOTE"]
p = ".copier-answers.yml"
s = open(p, encoding="utf-8").read()
s2 = re.sub(r'^_src_path:.*$', "_src_path: " + url, s, count=1, flags=re.M)
if s2 != s:
    open(p, "w", encoding="utf-8").write(s2)
PY
else
  echo "HARNESS: у шаблона нет remote.origin — _src_path остался локальным путём," >&2
  echo "         значит copier update сработает только на этой машине." >&2
fi

# Дорендер трёх файлов. Незаменённый плейсхолдер ломает харнесс молча, поэтому список замен
# держим полным: чего в нём нет — то и приедет в инстанс угловыми скобками.
# `<WIKI_PATH>` из списка убран 14.08 вместе с самим плейсхолдером: он подставлялся ПУСТОТОЙ
# всегда (личный путь в версионируемый файл попадать не должен), и промпт SessionEnd в итоге
# велел дописывать лог в `/log` — в корень файловой системы. Адрес вики теперь берётся в рантайме
# из личного конфига `~/.harness/`, шаблон его не знает вовсе.
render() {
  sed -e "s|<PROJECT_NAME>|$NAME|g" \
      -e "s|{{PROJECT}}|$NAME|g" \
      -e "s|<PACKAGE_PATH>|$PKG_PATH|g" \
      -e "s|<WATCH_DIR>|$WATCH_DIR|g" \
      -e "s|<TEST_CMD>|$TEST_CMD|g" \
      -e "s|<READONLY_ZONES>|$READONLY|g" \
      -e "s|<LANG_AND_VERSION>|$LANG_VER|g" \
      -e "s|<BUILD_TOOL>|$BUILD_TOOL|g" \
      -e "s|<TEST_FRAMEWORK>|$TEST_FW|g" \
      -e "s|<OTHER_TOOLS>|$OTHER_TOOLS|g" \
      -e "s|<FRAMEWORK_AND_VERSION>|$TODO_MARK|g" \
      -e "s|<MODULE_DIR>|$TODO_SHORT|g" \
      -e "s|<SHARED_DIR>|$TODO_SHORT|g" \
      -e "s|<ENTRY_POINT>|$TODO_SHORT|g" \
      -e "s|<UNIT_PATTERN>|$TODO_MARK|g" \
      -e "s|<TYPING_RULE>|$TODO_MARK|g" \
      -e "s|<QA_MARKER>|$TODO_MARK|g" \
      -e "s|<REFERENCE_PATH>|$TODO_MARK|g" \
      -e "s|<ENTITIES>|$TODO_MARK|g" \
      -e "s|<DATA_SOURCE>|$TODO_MARK|g" \
      -e "s|<DATA_INVARIANT>|$TODO_MARK|g" \
      -e "s|<MAIN_FLOW>|$TODO_MARK|g" \
      -e "s|<STATE_TRANSITIONS>|$TODO_MARK|g" \
      -e "s|<ACCESS_RULES>|$TODO_MARK|g" "$1"
}

render "$TPL/skeleton/CLAUDE.md.template" > CLAUDE.md

mkdir -p .claude
render "$TPL/skeleton/.claude/settings.json.template" \
  | sed "s|run-test-hook.sh|$SENSOR|g" > .claude/settings.json

# Doc-каркас. Copier их не привозит: .claude/docs в _exclude, плюс маска *.template.
mkdir -p .claude/docs
for DOC in ARCHITECTURE gotchas REVIEW model-policy dor-gate completion background-offload testing-guide; do
  render "$TPL/skeleton/.claude/docs/$DOC.md.template" > ".claude/docs/$DOC.md"
done

# Лог проекта. В скелете его нет: PENDING-NOTES пишет в вику через WIKI_PATH,
# а на чужой машине вики не будет. Дата подставляется на генерации, иначе в логе
# осталась бы дата шаблона.
mkdir -p docs
cat > docs/log.md <<LOG
# Лог — $NAME

> Записи новыми сверху. Одна запись — один смысловой шаг: что сделал, что удивило,
> что дальше. Заполняется по ходу, не постфактум: восстановленный вечером лог теряет
> ровно то, что было неочевидно днём.

## $(date +%Y-%m-%d) — разворот

Инстанс развёрнут через bootstrap. Тесты: \`$TEST_CMD\`.
LOG

if [[ "$WITH_AGENTS" == yes ]]; then
  mkdir -p .claude/agents
  # Только файлы с YAML-фронтматтером: Claude Code читает `.claude/agents/*.md` как ОПРЕДЕЛЕНИЯ
  # субагентов, а глоб `*.md` тащил туда ещё и README пакета — документацию в рантайм-каталог.
  # Ревью 14.08 нашло хуже самой протечки: ассерт в verify-bootstrap ждал «3 файла» и объяснял
  # число ролями, хотя ролей две. Тест закрепил дефект как контракт.
  for AGENT_FILE in "$TPL/skeleton/.claude/agents/"*.md; do
    [[ -f "$AGENT_FILE" ]] || continue
    [[ "$(head -1 "$AGENT_FILE")" == "---" ]] || continue
    cp "$AGENT_FILE" .claude/agents/
  done
fi

cat > docs/MOC.md <<'MOC'
# MOC — карта проекта

> В каком порядке это читать. Круги по времени, не по важности:
> круга 0 достаточно, чтобы начать работу.
>
> Круги — про чтение. Слово «ярус» в этом харнессе занято другим: ярусы 0–3 это ступени
> проверки (pre-commit → sensor → gate → pre-push), см. `.claude/rules/common/testing.md`.
> Раньше обе шкалы назывались ярусами, и в одном проекте жили «ярус 0 = начни отсюда» и
> «ярус 0 = линт на коммите».

## Круг 0 — минимум перед первой правкой

- `CLAUDE.md` — правила и роутинг, грузится всегда
- `docs/specs/spec-*.md` — активная спека среза. Нет спеки → код не начинаем

## Круг 1 — устройство проекта

- `.claude/docs/ARCHITECTURE.md` — стек, структура, инварианты, модель данных, бизнес-логика
- `docs/log.md` — что происходило и что удивило

## Круг 2 — по нужде

- `.claude/docs/gotchas.md` — правила, найденные на реальной работе (§-нумерация)
- `.claude/docs/REVIEW.md` — чеклист ревью
- `.claude/docs/model-policy.md` — какой моделью что делать и что делать, когда агент не вернулся
- `.claude/agents/` — роли-агенты, если раскатаны флагом `--agents`

## Как это пополняется

Находка при разборе кода → секция в `ARCHITECTURE.md`.
Грабли, которые повторятся → `§` в `gotchas.md`.
Что произошло за сессию → запись в `docs/log.md`, новыми сверху.
MOC

cat > .harness.conf <<CONF
# Сгенерировано bootstrap.sh для lang=$LANG_PACK
WATCH_DIR="$WATCH_DIR"
TEST_CMD="$TEST_CMD"
$PY_CONF_BLOCK
READONLY_ZONES="$READONLY"
GATE_CMD="$GATE_CMD"
GATE_TEST_CMD="$GATE_TEST_CMD"
GATE_WORKDIR=""
# Секрет-скан на Ярусе 3 (пусто → pre-push пишет строкой, что скана нет).
SECRET_SCAN_CMD=""
# WIKI_PATH тут нет: файл версионируется, адрес вики личный. Личный слой —
# ~/.harness/<имя-каталога-репо>.conf, load-context.sh читает его после этого файла.
# Сверка «критерий приёмки ↔ тест» (scripts/check-ac-refs.sh). ID из чекбоксов секции
# Verification спеки обязан встречаться хотя бы в одном тесте. Пустой AC_TEST_GLOBS →
# проверка молчит и не работает: маски тестов зависят от стека, дефолта на все языки нет.
AC_ID_RE="AC-[0-9]+"
AC_TEST_GLOBS="$AC_GLOBS"
AC_TEST_DIR="\$REPO_ROOT${AC_DIR:+/$AC_DIR}"
COVERAGE_REPORT=""
DIFF_COVER_BASE=""
DIFF_COVER_BASELINE="\$REPO_ROOT/scripts/check-diff-coverage.baseline"
CONF

# Эти пять скриптов уже привозит `copier copy` выше — `scripts` в `_exclude` не входит.
# Безусловный `cp` тут был мёртвым шагом: перезаписывал файл тем же содержимым. Оставлена
# СТРАХОВКА с диагностикой: если copier его не привёз (кто-то добавил путь в `_exclude`), файл
# всё равно появится, но расхождение будет названо вслух, а не замаскировано копией.
mkdir -p scripts
ensure_core_script() {
  local name="$1" why="$2"
  if [[ ! -f "scripts/$name" ]]; then
    echo "HARNESS: copier не привёз scripts/$name — копирую напрямую. Проверь _exclude в copier.yml." >&2
    echo "         зачем нужен: $why" >&2
    cp "$TPL/skeleton/scripts/$name" "scripts/$name"
  fi
  chmod +x "scripts/$name"
}

# SessionStart в settings.json смотрит на этот файл по имени.
ensure_core_script load-context.sh "SessionStart: активные спеки и долгая память"
# rules/common/workflow.md и скил end-session требуют его ПО ИМЕНИ и запрещают Edit для лога.
ensure_core_script log-append.sh "append в лог вместо Edit"
# На него ссылается шаблон спеки (docs/specs/_template.md).
ensure_core_script check-ac-refs.sh "сверка критерий приёмки ↔ тест"
# Ярус 3, шаг 5 (покрытие идёт последним: отчёт создают тесты шага 4).
ensure_core_script check-diff-coverage.sh "покрытие изменённых строк"
# Смоук харнесса: README посылает сюда после раскатки.
ensure_core_script verify-harness.sh "смоук: guard блокирует, sensor/gate живы, /note на месте"

# Пороги ratchet. На свежем инстансе непокрытых нуль, поэтому ноль честен. Без файла скрипты
# считают порогом ноль и предупреждают об отсутствии — лучше создать явно.
echo 0 > scripts/check-ac-refs.baseline
echo 0 > scripts/check-diff-coverage.baseline

# Карта раскладки реестра ловушек. Суффикс `.template` снимаем: скрипт зовёт файл по имени
# `gotchas-partition.map`, а копия «как есть» оставила бы его без карты — то есть при первом
# прогоне весь реестр уехал бы в архив.
if [[ -f "$TPL/skeleton/scripts/gotchas-partition.map.template" ]]; then
  cp "$TPL/skeleton/scripts/gotchas-partition.map.template" scripts/gotchas-partition.map
fi

# Активация Яруса 3. Логика — в .claude/guards/pre-push.sh (версионируется, едет обоими
# каналами), тут только включение: git-хук работает на любом стеке и не требует npm.
# husky остаётся опцией для команд, которые шарят хуки через package.json.
mkdir -p .git/hooks
cat > .git/hooks/pre-push <<'HOOK'
#!/usr/bin/env sh
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sh "${REPO_ROOT}/.claude/guards/pre-push.sh"
HOOK
chmod +x .git/hooks/pre-push

if [[ "$LANG_PACK" == python ]]; then
  mkdir -p tests
  cat > tests/test_smoke.py <<'PY'
def test_smoke() -> None:
    """Доказывает, что петля жива до первой строки задачи."""
    assert 1 + 1 == 2
PY
  uv run pytest -q
fi

echo
echo "Готово: $NAME (lang=$LANG_PACK)."
echo "Первый шаг — копия docs/specs/_template.md → docs/specs/spec-<дата>-<срез>.md."
echo "Нет файла спеки с заполненными AC → код не начинаем."
