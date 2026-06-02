# minimal-harness

Минимальный рабочий харнесс. Клонируй, заполни `.harness.conf`, запусти.

## Что есть

- **Guard** — блокирует запись в `dist/` (exit 2)
- **Sensor** — запускает тесты после Edit в `src/` (mute the green)

## Как использовать

```bash
# 1. Скопируй .claude/ в корень своего проекта
cp -r examples/minimal/.claude ./
cp examples/minimal/.harness.conf .harness.conf

# 2. Отредактируй .harness.conf
#    WATCH_DIR=src, READONLY_ZONES=dist, TEST_CMD=...

# 3. Сделай скрипты исполняемыми
chmod +x .claude/guards/*.sh

# 4. Проверь
bash scripts/verify-harness.sh
```

## Что настроить

| Параметр | По умолчанию | Твоё значение |
|----------|-------------|--------------|
| `WATCH_DIR` | `src` | папка с исходниками |
| `READONLY_ZONES` | `dist` | что guard блокирует |
| `TEST_CMD` | `npx vitest related --run` | команда тестов |

Для расширенной конфигурации — смотри `skeleton/`.
