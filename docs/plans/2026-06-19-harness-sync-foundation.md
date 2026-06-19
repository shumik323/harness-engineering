# Harness Sync Foundation (Фазы A+B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать харнессу наблюдаемость дрейфа (карта) и версионируемый sync CORE-слоя через Copier, с обратным каналом в темплейт.

**Architecture:** Харнесс делится на 3 слоя (CORE/LANG/LOCAL). Синкается только CORE. Вниз — `copier update`, вверх — скрипт-помощник PR. Наблюдаемость — послойный diff-скрипт + реестр.

**Tech Stack:** bash/zsh, Copier (через pipx), git, macOS/darwin.

## Global Constraints

- Синкается **только CORE** (guards, skills/{note,end-session,task}, rules/common). LANG и LOCAL не синкаются.
- LOCAL инстанса (`CLAUDE.md`, `docs/{ARCHITECTURE,gotchas,REVIEW}`, проектные skills, plans) при синке **не трогать**.
- Copier ставится через **pipx** (`pipx install copier`). Python 3.12 уже есть.
- Пилот `copier update` — только на **turbo-omni** (урезанный, безопасно). На abdulpay не раскатывать до успеха пилота.
- **fenris-frontend-vue вне этой итерации** — приведён в отдельной ветке, интегрируется после.
- Источник правды — `harness-template`. Команды запускать из `~/Desktop/space307`.
- Коммитить только по явному запросу пользователя (правило git.md). Шаги «Commit» в плане выполняются после устного «commit».

---

### Task A1: Скрипт послойного дрейфа `harness-status.sh`

**Files:**
- Create: `harness-template/scripts/harness-status.sh`
- Create: `harness-template/scripts/lib/layers.sh` (определение слоёв — переиспользуется в B4)

**Interfaces:**
- Produces: `harness-status.sh <instance-path>` — печатает дрейф по слоям; exit 1 если CORE-дрейф найден.
- Produces: `layers.sh` экспортирует `CORE_PATHS` (массив glob CORE-файлов относительно `.claude`).

- [ ] **Step 1: Определить CORE-слой в `lib/layers.sh`**

```bash
#!/usr/bin/env bash
# Пути CORE-слоя относительно корня инстанса. Только это синкается.
CORE_PATHS=(
  ".claude/guards/block-zones.sh"
  ".claude/guards/gate.sh"
  ".claude/guards/run-test-hook.sh"
  ".claude/skills/note/append.sh"
  ".claude/skills/note/SKILL.md"
  ".claude/skills/end-session/SKILL.md"
  ".claude/skills/task/SKILL.md"
  ".claude/rules/common/git.md"
  ".claude/rules/common/testing.md"
  ".claude/rules/common/workflow.md"
)
```

- [ ] **Step 2: Написать `harness-status.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/layers.sh"
TPL="$HERE/../skeleton"
INSTANCE="${1:?usage: harness-status.sh <instance-path>}"

drift=0
echo "== CORE drift: $INSTANCE =="
for p in "${CORE_PATHS[@]}"; do
  tpl_file="$TPL/$p"; [ -f "$tpl_file" ] || tpl_file="$TPL/$p.template"
  inst_file="$INSTANCE/$p"
  if [ ! -f "$inst_file" ]; then echo "  MISSING  $p"; drift=1
  elif ! diff -q "$tpl_file" "$inst_file" >/dev/null 2>&1; then echo "  DIVERGED $p"; drift=1
  else echo "  ok       $p"; fi
done
[ "$drift" -eq 0 ] && echo "CORE clean" || echo "CORE drift detected"
exit "$drift"
```

- [ ] **Step 3: Сделать исполняемым и прогнать против turbo-omni**

Run:
```bash
chmod +x harness-template/scripts/harness-status.sh
harness-template/scripts/harness-status.sh ~/Desktop/space307/space307-project/turbo-omni
```
Expected: строки `DIVERGED .claude/guards/gate.sh`, `MISSING .claude/rules/common/git.md`, финал `CORE drift detected`, exit 1.

- [ ] **Step 4: Прогнать против abdulpay**

Run: `harness-template/scripts/harness-status.sh ~/Desktop/space307/space307-project/abdulpay-frontend; echo "exit=$?"`
Expected: `gate.sh` → `ok`; rules/common → `ok`; exit 0 или 1 в зависимости от мелкого дрейфа. Зафиксировать фактический вывод.

- [ ] **Step 5: Commit**

```bash
git -C harness-template add scripts/harness-status.sh scripts/lib/layers.sh
git -C harness-template commit -m "feat(A): послойный harness-status.sh + определение CORE"
```

---

### Task A2: Реестр `REGISTRY.md`

**Files:**
- Create: `harness-template/REGISTRY.md`

**Interfaces:**
- Consumes: вывод `harness-status.sh` из Task A1.

- [ ] **Step 1: Собрать факты по каждому инстансу**

Run:
```bash
for d in abdulpay-frontend turbo-omni; do
  echo "## $d"; git -C ~/Desktop/space307/space307-project/$d remote get-url origin
  harness-template/scripts/harness-status.sh ~/Desktop/space307/space307-project/$d | tail -1
done
```

- [ ] **Step 2: Записать `REGISTRY.md`** (реальные значения из Step 1, не плейсхолдеры)

```markdown
# Harness Registry

Источник правды CORE: harness-template. Дрейф сверяется `scripts/harness-status.sh`.

| Проект | Remote | HARNESS_VERSION | CORE-дрейф (2026-06-19) |
|---|---|---|---|
| abdulpay-frontend | affiliate/abdulpay-frontend | — (до Task B1) | <из прогона> |
| turbo-omni | md/omni/terra | — | CORE drift detected |
| fenris-frontend-vue | affiliate/fenris-frontend-vue | — | вне итерации (ветка) |
```

- [ ] **Step 3: Commit**

```bash
git -C harness-template add REGISTRY.md
git -C harness-template commit -m "feat(A): REGISTRY.md — карта инстансов и дрейфа"
```

---

### Task B1: Установка Copier + версия харнесса

**Files:**
- Modify: `harness-template/skeleton/.harness.conf.example`
- Modify: `harness-template/README.md` (раздел setup — добавить установку Copier)
- Create: `harness-template/VERSION`

**Interfaces:**
- Produces: `HARNESS_VERSION` в `.harness.conf`; `VERSION` в корне темплейта (single source).

- [ ] **Step 1: Установить pipx и Copier**

Run:
```bash
brew install pipx && pipx ensurepath
pipx install copier
copier --version
```
Expected: печатает версию Copier (например `copier 9.x`).

- [ ] **Step 2: Создать `VERSION`**

Run: `echo "0.1.0" > harness-template/VERSION`

- [x] ~~**Step 3: Добавить `HARNESS_VERSION` в `.harness.conf.example`**~~ — ПЕРЕСМОТРЕНО 2026-06-19.
  Поле оказалось мёртвым: Copier пишет версию в `.copier-answers.yml`, НЕ в `.harness.conf`, и
  `HARNESS_VERSION` никто не читал (harness-status сверяет diff'ы файлов, не версию). Удалено;
  `.harness.conf.example` теперь содержит комментарий-указатель на `.copier-answers.yml`. См. лог
  [2026-06-19] fix в вики-проекте.

- [x] ~~**Step 4: Проверить** (`grep HARNESS_VERSION ...`)~~ — снято вместе со Step 3.

- [ ] **Step 5: Commit**

```bash
git -C harness-template add VERSION skeleton/.harness.conf.example README.md
git -C harness-template commit -m "feat(B): версия харнесса HARNESS_VERSION + установка Copier в setup"
```

---

### Task B2: Copier-шаблон на CORE + условный LANG

**Files:**
- Create: `harness-template/copier.yml`
- Modify: структура `skeleton/` (CORE без изменений; LANG — под `_when` условия)

**Interfaces:**
- Consumes: `CORE_PATHS` (концептуально — те же файлы).
- Produces: `copier.yml` с вопросами `project_name`, `lang` (vue/go/php/python/none); LANG-файлы рендерятся по `lang`.

- [ ] **Step 1: Написать `copier.yml`**

```yaml
_subdirectory: skeleton
_answers_file: .copier-answers.yml

project_name:
  type: str
  help: Имя проекта-инстанса

lang:
  type: str
  help: Языковой пак
  choices: [vue, go, php, python, none]
  default: vue
```

- [ ] **Step 2: Условный рендер LANG-файлов**

Переименовать языковые правила в условные шаблоны Copier (Jinja в имени файла). Пример для go:
```bash
cd harness-template/skeleton/.claude/rules/lang
git mv go.md "go.md{% if lang != 'go' %}.skip{% endif %}"   # иллюстрация подхода
```
Реализация: использовать `_exclude` в `copier.yml` по `lang` ИЛИ `{% if lang == 'vue' %}`-условие в пути. Выбрать `_exclude` — проще:
```yaml
_exclude:
  - "*.skip"
  - "{% if lang != 'vue' %}.claude/rules/lang/vue.md{% endif %}"
  - "{% if lang != 'go' %}.claude/rules/lang/go.md{% endif %}"
  - "{% if lang != 'php' %}.claude/rules/lang/php.md{% endif %}"
  - "{% if lang != 'python' %}.claude/rules/lang/python.md{% endif %}"
```

- [ ] **Step 3: Тест — рендер во временную папку с lang=vue**

Run:
```bash
TMP=$(mktemp -d); copier copy --data project_name=test --data lang=vue harness-template "$TMP" --defaults --trust
ls "$TMP/.claude/rules/lang/"
```
Expected: есть `vue.md`, **нет** `go.md`/`php.md`/`python.md`. CORE-файлы (`guards/gate.sh`, `rules/common/*`) присутствуют.

- [ ] **Step 4: Тест — lang=go даёт go.md, не vue.md**

Run: `TMP2=$(mktemp -d); copier copy --data project_name=t --data lang=go harness-template "$TMP2" --defaults --trust; ls "$TMP2/.claude/rules/lang/"`
Expected: есть `go.md`, нет `vue.md`.

- [ ] **Step 5: Commit**

```bash
git -C harness-template add copier.yml skeleton
git -C harness-template commit -m "feat(B): copier.yml — CORE всегда, LANG по выбору языка"
```

---

### Task B3: Пилот `copier update` на turbo-omni

**Files:**
- Modify: `turbo-omni/.copier-answers.yml` (создаётся Copier)
- Modify: `turbo-omni/.claude/guards/*` (подтянутся из CORE)

**Interfaces:**
- Consumes: `copier.yml` из B2.

- [ ] **Step 1: Снять бэкап LOCAL turbo-omni для последующей сверки**

Run: `cp -r ~/Desktop/space307/space307-project/turbo-omni/.claude/docs/ui-kit /tmp/uikit-before`

- [ ] **Step 2: Привязать turbo-omni к шаблону (первичный `copier copy` поверх)**

Run:
```bash
cd ~/Desktop/space307/space307-project/turbo-omni
copier copy --data project_name=turbo-omni --data lang=vue ~/Desktop/space307/harness-template . --trust --overwrite
```
Ожидание: появится `.copier-answers.yml`; CORE-файлы перезапишутся версией темплейта.

- [ ] **Step 3: Проверить, что LOCAL не тронут**

Run: `diff -r /tmp/uikit-before ~/Desktop/space307/space307-project/turbo-omni/.claude/docs/ui-kit && echo "LOCAL intact"`
Expected: `LOCAL intact` (без вывода diff).

- [ ] **Step 4: Проверить, что CORE-дрейф исчез**

Run: `~/Desktop/space307/harness-template/scripts/harness-status.sh ~/Desktop/space307/space307-project/turbo-omni; echo "exit=$?"`
Expected: `CORE clean`, exit 0.

- [ ] **Step 5: Проверить, что харнесс turbo-omni рабочий (gate не сломан)**

Run: `bash ~/Desktop/space307/space307-project/turbo-omni/.claude/guards/gate.sh --dry-run 2>&1 | head` (или эквивалент проверки синтаксиса)
Expected: скрипт парсится, не падает с синтаксической ошибкой.

- [ ] **Step 6: Commit (в репо turbo-omni, по запросу пользователя)**

```bash
cd ~/Desktop/space307/space307-project/turbo-omni
git checkout -b harness-sync
git add .claude .copier-answers.yml
git commit -m "chore: привязка к harness-template, sync CORE через Copier"
```

---

### Task B4: Обратный канал `harness-contribute.sh`

**Files:**
- Create: `harness-template/scripts/harness-contribute.sh`

**Interfaces:**
- Consumes: `lib/layers.sh` (CORE_PATHS) из A1.
- Produces: `harness-contribute.sh <instance-path>` — копирует изменённые CORE-файлы инстанса в темплейт и создаёт ветку для PR.

- [ ] **Step 1: Написать скрипт**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/layers.sh"
TPL="$HERE/../skeleton"
INSTANCE="${1:?usage: harness-contribute.sh <instance-path>}"
BRANCH="harness-contrib-$(date +%Y%m%d-%H%M%S)"

git -C "$HERE/.." checkout -b "$BRANCH"
changed=0
for p in "${CORE_PATHS[@]}"; do
  tpl_file="$TPL/$p"; [ -f "$tpl_file" ] || tpl_file="$TPL/$p.template"
  inst_file="$INSTANCE/$p"
  if [ -f "$inst_file" ] && ! diff -q "$tpl_file" "$inst_file" >/dev/null 2>&1; then
    cp "$inst_file" "$tpl_file"; echo "PULLED UP: $p"; changed=1
  fi
done
[ "$changed" -eq 1 ] && echo "Готова ветка $BRANCH — проверь diff и открой PR" || { echo "Нет CORE-изменений для контрибуции"; git -C "$HERE/.." checkout -; }
```

- [ ] **Step 2: Тест на фикстуре — внести правку в CORE инстанса и проверить подъём**

Run:
```bash
chmod +x harness-template/scripts/harness-contribute.sh
echo "# test-marker" >> ~/Desktop/space307/space307-project/abdulpay-frontend/.claude/rules/common/workflow.md
harness-template/scripts/harness-contribute.sh ~/Desktop/space307/space307-project/abdulpay-frontend
grep "test-marker" harness-template/skeleton/.claude/rules/common/workflow.md && echo "OK подъём сработал"
```
Expected: `PULLED UP: .claude/rules/common/workflow.md`, `OK подъём сработал`.

- [ ] **Step 3: Откатить тестовый маркер**

Run:
```bash
git -C harness-template checkout skeleton/.claude/rules/common/workflow.md
git -C harness-template checkout -  # вернуться с contrib-ветки
git -C ~/Desktop/space307/space307-project/abdulpay-frontend checkout .claude/rules/common/workflow.md
```

- [ ] **Step 4: Commit**

```bash
git -C harness-template add scripts/harness-contribute.sh
git -C harness-template commit -m "feat(B): harness-contribute.sh — обратный канал CORE в темплейт"
```

---

## Self-Review (выполнено при написании)

- **Spec coverage:** A (REGISTRY+status) → A1,A2 ✓; B (версия, Copier-вниз, контриб-вверх) → B1–B4 ✓; 3-слойная политика → `lib/layers.sh` + `_exclude` ✓; «синкаем только CORE» → CORE_PATHS ограничивает все скрипты ✓. C и D вне плана (отдельные циклы) — осознанно.
- **Placeholder scan:** конкретные пути/команды/ожидаемый вывод во всех шагах. В B2 Step2 показаны два подхода с явным выбором `_exclude` — не плейсхолдер, а решение.
- **Type consistency:** `CORE_PATHS` определён в A1, переиспользован в B4; `harness-status.sh` сигнатура одна; `VERSION`/`HARNESS_VERSION` согласованы (B1).
- **Открытый риск:** B2 Step2 — синтаксис Copier `_exclude` с Jinja проверяется прогоном в B2 Step3/4; если не сработает — fallback на `.skip`-суффиксы (показан в Step1).
