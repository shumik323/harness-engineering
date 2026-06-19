# Самообновляемый харнесс — дизайн

**Дата:** 2026-06-19
**Статус:** дизайн утверждён, переход к плану реализации
**Репозиторий:** harness-template (источник правды)

## Проблема

Харнесс раскатывается на инстансы ручным `cp skeleton/.claude`. Версии нет, обратного
канала нет. Результат — дрейф в обе стороны:

- темплейт **отстал** от инстансов: `rules/lang/md-libs.md` родился в abdulpay, в темплейт не вернулся
- инстанс **разошёлся по ядру**: turbo-omni имеет другие `gate.sh`, `block-zones.sh`,
  `run-test-hook.sh`, `note`, `task`, `end-session` — а это должно быть идентично везде
- улучшения умирают в инстансе, не доходя до остальных

Это классический config drift от copy-paste. Цель — замкнуть цикл: общее ядро тянется
вниз автоматически, доказавшие пользу правки идут вверх, агент сам предлагает улучшения.

## Факты (проверены прогоном 2026-06-19)

| Факт | Доказательство |
|---|---|
| abdulpay `gate.sh` идентичен темплейту, turbo-omni — разошёлся | md5: `0a85b10…` == template, turbo-omni `8500c75…` |
| Темплейт отстал | в skeleton нет `rules/lang/md-libs.md`, в abdulpay есть |
| Монорепы фронтов нет | `new-lerna-workspace` — пустая lerna-болванка, наших фронтов там нет |
| Инстансы — отдельные репо с разными remote | affiliate/abdulpay, affiliate/fenris, md/omni/terra |
| Copier не установлен | `copier not found`, Python 3.12 есть, pipx нет |
| Объём дрейфа: abdulpay 23 файла, turbo-omni 19, fenris 36 | `find .claude` |

Вывод из цифр: тяжёлая миграция в монорепу не оправдана. Гибрид (общее ядро +
локальная свобода) закрывает задачу без слияния репозиториев.

## Архитектура — 3 слоя харнесса

Харнесс не монолит. Три слоя, у каждого своя политика синка.

| Слой | Состав | Политика | Дрейф |
|---|---|---|---|
| **CORE** | guards, skills/{note,end-session,task}, rules/common | синк жёсткий, идентичен везде | дрейф = баг |
| **LANG** | rules/lang/*, lang-packs/* | инстанс берёт только свой пак (vue/go/php/python) | отсутствие чужих = норма |
| **LOCAL** | CLAUDE.md, docs/{ARCHITECTURE,gotchas,REVIEW}, проектные skills, plans | принадлежит инстансу | дрейф ожидаем |

Ключевое следствие: синкаем **только CORE**. Тогда Copier-конфликты не возникают на
LOCAL-правках — а значит работает даже на форкнутых инстансах.

## Самообновляемость — два канала + агент

```
harness-template (источник правды CORE + LANG-паки + copier.yml)
        │  ⬇ copier update (тянет новую версию CORE, LOCAL не трогает)
        ▼
   instance (.copier-answers.yml помнит версию)
        │  ⬆ harness-contribute.sh (готовит PR из инстанса в темплейт)
        ▼
harness-template  ← правка проходит ревью, становится новой версией CORE
```

- **⬇ вниз:** `copier update` в инстансе подтягивает новую версию CORE
- **⬆ вверх:** `scripts/harness-contribute.sh` собирает диф локального CORE-изменения и
  готовит PR в темплейт (закрывает требование двустороннего цикла)
- **🤖 self-improve:** skill `/harness-improve` читает `gotchas.md` и `PENDING-NOTES.md`,
  ловит повторяющуюся боль, предлагает правку CORE через канал вверх

## Наблюдаемость

- `harness-template/REGISTRY.md` — реестр: проект → remote → версия харнесса → дрейф по слоям
- `scripts/harness-status.sh` — гоняет послойный diff темплейт ↔ инстанс, печатает дрейф
  (CORE-дрейф помечает как ошибку, LOCAL — как норму)

## Версионирование

Источник версии инстанса — `.copier-answers.yml` (его пишет Copier при copier copy/update).
~~Дублирующий `HARNESS_VERSION` в `.harness.conf`~~ — отклонено 2026-06-19: мёртвое поле, никто
не читает, молча расходится с copier-answers.

## Фазы реализации

- **Фаза 0 — факты.** Снапшоты + полный послойный diff. ✓ закрыто 2026-06-19.
- **Фаза A — карта.** REGISTRY.md + harness-status.sh.
- **Фаза B — версия + sync.** HARNESS_VERSION; copier.yml на CORE; пилот `copier update`
  на turbo-omni (урезанный, безопасно); harness-contribute.sh.
- **Фаза C — self-improve.** Skill `/harness-improve` поверх `/note` → `/end-session`.
- **Фаза D — роли-агенты.** Worktrees + субагенты creator/verifier/bugfixer. По реальной боли.

fenris-frontend-vue в первую итерацию не входит — приведён в порядок в отдельной ветке,
интегрируется после её мержа.

## Решения (ADR-кратко)

- **Гибрид, не монорепа.** Дрейф умеренный, инстансы — отдельные продукты с разными remote.
  Слияние репо не оправдано. → фиксируется в `docs/decisions.md`.
- **Copier, не cookiecutter/subtree.** Только Copier умеет `update` (template→project merge).
- **Синкаем только CORE.** Снимает хрупкость Copier на локальных правках.
- **Обратный канал — отдельный процесс (PR), не Copier.** Copier односторонний by design.

## Риски

- `copier update` хрупок при конфликтах, откат нетривиален → митигируем тем, что синкаем
  только CORE; пилот на turbo-omni до раскатки на abdulpay.
- Copier как зависимость (нужен Python/pipx) → задокументировать установку в setup.

## Критерии готовности (как проверить)

- `scripts/harness-status.sh` печатает дрейф каждого инстанса по слоям, CORE-дрейф виден
- `copier update` на turbo-omni подтягивает CORE и **не трогает** LOCAL (docs/ui-kit, plans)
- `harness-contribute.sh` из правки в abdulpay формирует корректный PR-диф в темплейт
- `REGISTRY.md` отражает реальные версии (сверяется с `.copier-answers.yml` инстансов)
- правило завершения (онбординг + «как проверить») вынесено в `rules/common/workflow.md`
