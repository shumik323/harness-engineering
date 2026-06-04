# harness-template — мета-харнесс

Эта репо — **шаблон** харнессов Claude Code / Cursor. Ты работаешь внутри него.

> **Dual-tool.** Шаблон рассчитан и на **Claude Code**, и на **Cursor** — оба в работе.
> `.claude/` и `.cursor/hooks.json` делегируют к одним и тем же `guards/`-скриптам.

## Два слоя — не путать

| Слой | Путь | Назначение |
|------|------|-----------|
| Харнесс этой репы | `.claude/` | Правила для работы над самим шаблоном |
| Шаблон для потребителя | `skeleton/` | Копируется в ui-kit и другие репо |

Изменяя `.claude/` — меняешь как работаешь ТУТ.
Изменяя `skeleton/` — меняешь что получит потребитель.

**Dogfood тут намеренно лёгкий:** в репе-шаблоне нет билда и тест-сьюта, поэтому
sensor/guard не нужны. Но capture-flow догфудим — `.claude/skills/note/` живой,
наблюдения по ходу работы над шаблоном кидаем в `/note`.

## Принципы

- **Generic ≠ пустой.** Переносится структура + параметризованные скрипты + методология. Стек и правила — нет.
- **Параметризация вместо хардкода.** Все пути через переменные: `WATCH_DIR`, `READONLY_ZONES`, `TEST_CMD`, `WIKI_PATH`.
- **Dogfood.** Эта репо сама построена по правилам которые проповедует.
- **Mute the green.** Хуки молчат при успехе. Сигналят только при провале.
- **Строй от отказов.** MVP-набор, остальное по реальной боли.

## Поток изменений

```
1. Изменяешь skeleton/ (generic)
2. Применяешь instance в turbo-omni/ (ui-kit)
3. Проверяешь что ui-kit работает
→ компонент закрыт в обоих репо
```

## Правило: обновлять диаграммы при изменении структуры

При любом изменении структуры `skeleton/` или добавлении нового компонента харнесса:
- Обновить соответствующую Mermaid-диаграмму в `README.md`
- Три диаграммы: **Два слоя репо** / **Runtime flow** / **Skeleton → Instance**
- Диаграммы — единственная живая документация структуры для людей и агентов

## Параметры конфигурации (`.harness.conf`)

| Переменная | Описание | Пример (ui-kit) |
|-----------|----------|-----------------|
| `WATCH_DIR` | Где sensor следит за изменениями | `packages/ui-kit/lib` |
| `READONLY_ZONES` | Что guard блокирует | `dist storybook-static` |
| `TEST_CMD` | Команда сенсора (пофайлово) | `vitest related --run` |
| `GATE_CMD` | Команда gate (repo-wide: typecheck+lint+build) | `turbo type-check lint build` |
| `WIKI_PATH` | Путь к долгосрочной памяти | `/Users/.../TechWiki/ui-kit-harness/` |

## Структура skeleton/

```
skeleton/
├── CLAUDE.md.template          ← роутер с плейсхолдерами
├── PACKAGE_CLAUDE.md.template  ← guide пакета (generic)
├── .claude/
│   ├── settings.json.template  ← хуки: PreToolUse (guard), PostToolUse (sensor), Stop (gate), SessionStart/End
│   ├── guards/
│   │   ├── block-zones.sh      ← блокирует READONLY_ZONES
│   │   ├── run-test-hook.sh    ← sensor: TEST_CMD после Edit/Write (пофайлово)
│   │   └── gate.sh             ← gate: GATE_CMD на Stop + pre-push (repo-wide, loop-safe)
│   ├── skills/                 ← команды-skills (текущий стандарт, не commands/)
│   │   ├── note/               ← /note: capture в PENDING-NOTES.md
│   │   ├── task/               ← /task: шаблон промпта
│   │   └── end-session/        ← /end-session: triage + лог
│   ├── rules/                  ← common-core + per-language (path-scoped)
│   │   ├── common/             ← workflow, testing, git (грузятся всегда)
│   │   └── lang/               ← vue.md, go.md, php.md (frontmatter paths:)
│   └── docs/                   ← проектная память в git (JIT, по требованию)
│       ├── ARCHITECTURE.md.template  ← generic: стек, структура, паттерны
│       ├── REVIEW.md.template        ← generic чеклист ревью
│       └── gotchas.md.template       ← реестр найденных ловушек (§-нумерация)
├── lang-packs/                 ← языковые пакеты поверх ядра
│   └── vue/                    ← пример: add-component skill, dev-guide, Vue-ревью
├── scripts/
│   └── load-context.sh         ← SessionStart: грузит внешнюю вики (один из вариантов)
├── .cursor/
│   └── hooks.json              ← делегирует к .claude/guards/ (dual-tool)
└── .harness.conf.example       ← все параметры с комментариями
```

## Долгосрочная память — два слоя

`.claude/docs/` и внешняя вики решают разные задачи. Это не OR — это AND:

| Слой | Что хранит | Версионируется | Кто читает |
|------|-----------|---------------|------------|
| `.claude/docs/` | Архитектура, паттерны, review-правила | Да (git) | Команда + CI + агенты |
| Внешняя вики (через `load-context.sh`) | Лог сессий, личный нарратив, ADR-мотивации | Нет | Только ты + Claude |

`.claude/docs/` грузится по требованию через `@.claude/docs/ARCHITECTURE.md` — не автоматически.
`load-context.sh` — один из вариантов памяти. Можно не использовать вообще.
