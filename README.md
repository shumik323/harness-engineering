# harness-template

Шаблон харнесса Claude Code / Cursor для Vue/TS монорепо.

Харнесс = `CLAUDE.md` + хуки + гарды + команды + связь с долгосрочной памятью.

---

## 5-шаговый setup

```bash
# 1. Скопируй skeleton в корень своего проекта
cp -r skeleton/.claude ./
cp skeleton/.harness.conf.example .harness.conf

# 2. Заполни .harness.conf под свой проект
#    WATCH_DIR, READONLY_ZONES, TEST_CMD, WIKI_PATH

# 3. Сделай скрипты исполняемыми
chmod +x .claude/guards/*.sh

# 4. Создай CLAUDE.md из шаблона
cp skeleton/CLAUDE.md.template CLAUDE.md
# Замени плейсхолдеры: <PROJECT_NAME>, <PACKAGE_PATH>, <STACK>

# 5. Проверь харнесс
bash scripts/verify-harness.sh
```

---

## Структура репо

> Диаграммы выше обновляются вручную при изменении структуры (правило в `CLAUDE.md`).
> Если хотите живую автогенерацию — смотрите в сторону [repomix](https://github.com/yamadashy/repomix) или `tree -I node_modules`. Оверхед на CI, но всегда актуально.


```
harness-template/
├── CLAUDE.md                       ← правила для работы над самим шаблоном
├── .claude/                        ← харнесс этой репы (dogfood)
│   ├── guards/
│   └── commands/
├── skeleton/                       ← копируется в потребителя
│   ├── CLAUDE.md.template          ← роутер с плейсхолдерами
│   ├── PACKAGE_CLAUDE.md.template  ← guide пакета с плейсхолдерами
│   ├── .claude/
│   │   ├── settings.json.template  ← хуки: SessionStart, PostToolUse, Stop
│   │   ├── guards/
│   │   │   ├── block-zones.sh      ← читает READONLY_ZONES из .harness.conf
│   │   │   └── run-test-hook.sh    ← читает WATCH_DIR + TEST_CMD
│   │   ├── commands/
│   │   │   ├── add-component.md    ← скаффолдинг компонента
│   │   │   └── end-session.md      ← обновление лога в конце сессии
│   │   └── docs/                   ← проектная память (JIT, по требованию)
│   │       ├── ARCHITECTURE.md.template
│   │       ├── REVIEW.md.template
│   │       └── dev-guide.md.template
│   ├── scripts/
│   │   └── load-context.sh         ← SessionStart: грузит внешнюю вики
│   ├── .cursor/
│   │   └── hooks.json              ← делегирует к .claude/guards/
│   └── .harness.conf.example       ← все параметры с комментариями
├── examples/minimal/               ← рабочий пример (клонируй и запусти)
├── scripts/
│   └── verify-harness.sh           ← smoke test (guard exit 2, sensor green)
└── docs/
    └── specify-implement-review.md ← методология Specify → Implement → Review
```

---

## Параметры конфигурации (.harness.conf)

| Переменная | Описание | Пример (ui-kit) |
|-----------|----------|-----------------|
| `WATCH_DIR` | Директория для sensor-хука | `packages/ui-kit/lib` |
| `READONLY_ZONES` | Запрещённые для записи зоны | `dist storybook-static` |
| `TEST_CMD` | Команда тестов | `vitest related --run` |
| `WIKI_PATH` | Путь к долгосрочной памяти | `/path/to/TechWiki/ui-kit-harness` |

---

## Долгосрочная память: выбирай своё

`load-context.sh` в скелетоне — пример одного подхода: грузить `overview.md` + `log.md` из внешней вики (TechWiki, Notion, Confluence).

Это не стандарт. Три рабочих варианта:

| Вариант | Где хранить | Когда выбирать |
|---------|-------------|----------------|
| `.claude/docs/` | В репо (в git) | Команда, CI-агенты, нужна версионируемость |
| Внешняя вики | TechWiki / Notion / Confluence | Личный нарратив, кросс-проектный контекст |
| Только CLAUDE.md | Нигде отдельно | Маленький проект, один разработчик |

`.claude/docs/` грузится **по требованию** через `@.claude/docs/ARCHITECTURE.md` в промпте — не автоматически при старте. Это JIT (just-in-time): не засоряет контекст когда не нужен.

Шаблоны в `skeleton/.claude/docs/` — отправная точка. Выброси что не нужно, добавь своё.

**Принцип один: агент надёжен настолько, насколько надёжна среда вокруг него.
Как выстраивать эту среду — решаешь ты.**

---

## When NOT to use

- Проект < 1 недели жизни — overhead не окупится
- Нет тестов — sensor без тестов бесполезен
- Один разработчик без AI-агентов — харнесс для агентов, не для людей

---

## Первый instance

`turbo-omni/packages/ui-kit` — Vue 3 компонентная библиотека.
Харнесс здесь — forcing function: шаблон считается готовым только когда ui-kit на нём реально работает.
