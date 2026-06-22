# Harness Registry

Источник правды CORE-слоя: **harness-template** (`skeleton/`).
Дрейф сверяется `scripts/harness-status.sh <instance-path>` (exit 1 при CORE-дрейфе).

CORE-слой = guards + skills/{note,end-session,task} + rules/common. Только он синкается.
LANG (rules/lang/*) и LOCAL (CLAUDE.md, docs, проектные skills) — не синкаются, дрейф там ожидаем.

| Проект | Remote | HARNESS_VERSION | CORE-дрейф (2026-06-19) |
|---|---|---|---|
| abdulpay-frontend | affiliate/abdulpay-frontend | — (до Task B1) | почти clean: разошёлся только `rules/common/workflow.md` |
| turbo-omni | md/omni/terra | — | сильный: 6 DIVERGED (guards+skills) + 3 MISSING (rules/common/*) |
| fenris-frontend-vue | affiliate/fenris-frontend-vue | — | вне итерации — приведён в отдельной ветке, интегрируется после мержа |

## Задачи

- [ ] [P1] Раскатать `v0.1.1` в инстансы: `copier update` + `harness-status.sh` для проверки дрейфа после (abdulpay, fenris, turbo-omni). turbo-omni — сильный дрейф, лить осознанно (вероятны конфликты Copier).
- [ ] [P2] Перенести FSD-правило из CORE `workflow.md` в LANG `vue.md` (FSD — фронтовая специфика, в CORE мёртвый груз для go/php/python), тег `v0.1.2`. После — `copier update` на abdulpay уберёт намеренный дрейф `workflow.md` (см. HANDOFF abdulpay).

## Как обновить эту таблицу

```bash
for d in abdulpay-frontend turbo-omni; do
  echo "== $d =="
  scripts/harness-status.sh ~/Desktop/space307/space307-project/$d | tail -1
done
```

После Task B1 колонка `HARNESS_VERSION` берётся из `.copier-answers.yml` каждого инстанса.
