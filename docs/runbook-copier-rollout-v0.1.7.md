# Runbook — раскатка харнесса v0.1.7 на инстансы

> Исполнять **в сессии Claude внутри целевой репы**, не из корня шаблона.
> Причина: `copier update` механический, но разрешение конфликтов + ручные гэпы + верификация
> требуют контекста цели (её `.claude/` грузится только в её сессии). Из корня в контексте
> чужие правила (CLAUDE.md шаблона) — мешают ручному wiring.

Шаблон: `/Users/shumik/Desktop/space307/harness-template`, тег `v0.1.7`.

## Цели этой раскатки

| Репа | Состояние | Действие |
|------|-----------|----------|
| `abdulpay-frontend` | copier `v0.1.2`, дерево грязное | `copier update` → v0.1.7 |
| `turbo-omni` | НЕ под copier (ранний ручной `.claude`), дерево чистое, lang=vue | усыновить: `copier copy` → v0.1.7 |
| `fenris*` | — | **пропускаем** (решение владельца, эта раскатка не трогает) |

## Почему нужны ДВА ручных гэпа (оба инстанса)

`copier.yml` → `_exclude` исключает `*.template` и `.claude/settings.json.template`.
Значит copier **никогда** не доставит:
1. онбординг-блок «Агенту на входе» — он живёт в `skeleton/CLAUDE.md.template`;
2. проводку nudge-хука — она в `skeleton/.claude/settings.json.template`.

→ После copier-шага оба довешиваются **руками** в целевой репе. Это не баг, это известный
propagation-gap (см. wiki overview, P3 «закрыть gap»).

---

## A. abdulpay-frontend (update v0.1.2 → v0.1.7)

Путь: `/Users/shumik/Desktop/space307/space307-project/abdulpay-frontend`

1. **Чистое дерево** (copier требует). Сейчас грязное, с локальными правками харнесс-файлов
   (`.claude/rules/lang/vue.md`, `.claude/docs/gotchas.md`, `.harness.conf` и др.).
   → закоммитить или застэшить. **Git-зона владельца** — Claude не коммитит.
2. `copier update --defaults --trust --vcs-ref v0.1.7` (из корня репы).
   `--defaults` обязателен в агентской/non-TTY сессии: без него copier пытается спросить и
   падает (stdin не терминал). Эмпирически подтверждено на abdulpay.
3. **Конфликты ждать по харнесс-файлам с локальными правками** — 3-way merge оставит `.rej`
   или маркеры на `vue.md`, `gotchas.md`. Разрешать с учётом локальных кастомизаций abdulpay,
   не затирать вслепую.
4. **Ручные гэпы:**
   - `CLAUDE.md` → добавить блок «Агенту на входе» (источник: `skeleton/CLAUDE.md.template`).
   - `.claude/settings.json` → довесить `UserPromptSubmit` → `guards/nudge.sh`
     (источник: `skeleton/.claude/settings.json.template`). Проверить, что `nudge.sh` приехал
     copier-ом (он CORE) и `chmod +x`.
5. **Верификация (в этой же сессии):**
   - `/memory` — обновить.
   - смоук стека: `<TEST_CMD>` / сборка — харнесс не сломал инстанс.
   - **Дрейф CORE_PATHS делает НЕ эта сессия** — `harness-status.sh` лежит в `scripts/`
     шаблона, copier его в инстанс не возит. Гонится из КОРНЯ шаблона по пути инстанса:
     `bash scripts/harness-status.sh <путь-к-инстансу>`. Это задача корневой сессии.
6. Коммит (владелец). Сверить `.copier-answers.yml` → `_commit: v0.1.7`.

## B. turbo-omni (усыновление, copier copy → v0.1.7)

Путь: `/Users/shumik/Desktop/space307/space307-project/turbo-omni` · lang=vue · дерево чистое ✓

1. `copier copy --defaults --trust --vcs-ref v0.1.7 --data project_name=turbo-omni --data lang=vue \
      /Users/shumik/Desktop/space307/harness-template .`
   `--defaults` — чтобы copier не блокировал prompt'ом в non-TTY (хотя `--data` уже покрывает
   оба вопроса, флаг страхует от нового default-less вопроса в будущих версиях).
   На существующих файлах copier спросит overwrite — **не затирать вслепую**.
2. **Сверить старые гварды vs skeleton:** в turbo-omni уже есть `.claude/guards/gate.sh`,
   `block-zones.sh`, `run-test-hook.sh` (ранняя версия, возможно кастомизированы под ui-kit).
   Сравнить с приехавшими из skeleton, решить какие оставить. Старый `settings.json` тоже сверить.
3. **Заполнить `.harness.conf`** (его не было) — `WATCH_DIR`, `TEST_CMD`, `READONLY_ZONES`,
   `WIKI_PATH` под turbo-omni. Канон переменных — `skeleton/.harness.conf.example`.
4. **Те же два ручных гэпа** (CLAUDE.md онбординг + settings.json nudge) — см. раздел A п.4.
5. Проверить, что появился `.copier-answers.yml` с `_commit: v0.1.7` (значит дальше будет
   обычный `copier update`, без повторного усыновления).
6. **Верификация:** `/memory` + смоук сборки в этой сессии. Дрейф CORE_PATHS —
   из корня шаблона: `bash scripts/harness-status.sh <путь-к-инстансу>` (см. A.5, скрипт
   в инстанс не синкается).
7. Коммит (владелец).

---

## Отчёт обратно в корень (последний шаг — обязательно)

Корневая сессия (шаблон) на основе этого отчёта обновит wiki и решит, что тащить в skeleton.
Заполнить **по шаблону ниже** и отдать владельцу одним блоком. Главное различение:
**локальная кастомизация инстанса** (остаётся в инстансе) vs **баг/недоработка skeleton**
(чинится в корне через тег) — путать нельзя.

```
ОТЧЁТ: <repo> · <update|adopt> · v0.1.2→v0.1.7 / adopt
1. Copier-шаг: OK / упал на <чём>. Итог `.copier-answers.yml _commit`: <значение>
2. Конфликты (по файлам):
   - <файл> → решение: kept-local / took-template / merged. Почему.
   - …  (если конфликтов нет — «нет»)
3. Ручные гэпы:
   - CLAUDE.md онбординг-блок: довешен / нет
   - settings.json nudge-хук: довешен / нет · nudge.sh приехал+chmod: да/нет
4. Верификация:
   - harness-status.sh: PASS / <N fail: какие>
   - смоук (сборка/тесты): зелёные / <что упало>
   - /memory: обновил / нет
5. → В SKELETON (эскалация в корень): <что оказалось не локальной правкой, а баг/дырой
   шаблона — конкретный файл/строка>. Если ничего — «нет».
6. Боль/трение: <что бесило — особ. два ручных гэпа; кандидат в P3/gotcha>. Если нет — «нет».
```

Правило для п.5: если конфликт разрешён `took-template` или ты переписал то, что и так
едет из skeleton — это НЕ эскалация. Эскалация — когда skeleton привёз сломанное/устаревшее/
протекающее, и это словит ЛЮБОЙ инстанс. Только такое возвращается в корень.

## Переraскат на v0.1.8 (фикс block-zones)

Низкий приоритет: abdulpay (`dist`, top-level) и turbo-omni (полные пути) **сейчас защищены**
старым гвардом. v0.1.8 чинит вложенный `dist` для bare-имён + молчаливый fail-open на зоне
с хвостовым слешем. Можно батчить, не хотфикс.

1. `copier update --defaults --trust --vcs-ref v0.1.8` в каждом инстансе (дерево чистое).
2. **Проверка фикса:** подтвердить, что `block-zones` блокирует запись во ВЛОЖЕННУЮ зону при
   вашем `READONLY_ZONES` — попытка Edit в `<zone>/x` под `WATCH_DIR`-пакетом должна дать exit 2.
3. **Развилка turbo-omni:** с сегмент-матчем `packages/ui-kit/dist` можно свернуть в bare `dist` —
   но тогда защитятся `dist/` ВСЕХ пакетов монорепо (плюс или пере-блок — решение инстанса).
4. Дрейф из корня: `bash scripts/harness-status.sh <путь-к-инстансу>` → CORE clean.

## После раскатки (в корне, по отчётам)

- Обновить wiki `overview.md`: abdulpay v0.1.7 ✓, turbo-omni усыновлён ✓, fenris отложен.
- Запись в `log.md` (через `/end-session`).
- Если propagation-gap (два ручных гэпа) бесил — это сигнал поднять задачу: либо убрать
  `*.template`/`settings.json.template` из `_exclude` с осторожной jinja-логикой, либо
  отдельный init-скрипт довешивает их. P3 в бэклоге.
