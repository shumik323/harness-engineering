---
paths:
  - "**/*.py"
---

# Python — правила (грузятся только на *.py)

- **Расширяет `common/*`.** Здесь только Python-специфика, общее не дублировать.
- **`ruff` — формат и линт, не обсуждается.** `ruff format` + `ruff check --fix`.
  Заменяет black/isort/flake8. Стиль не правим руками.
- **`mypy` strict.** Публичные функции — с type hints. `Any` — осознанно и редко.
- **Тесты `pytest`.** Файлы `test_*.py` рядом с кодом или в `tests/`. Sensor гоняет
  их сам при правке (см. `run-pytest-hook.sh`) — отдельный ручной прогон без нужды
  не дублировать.
- **Запуск инструментов через `uv run`** если в проекте `uv` (`pyproject.toml`/`uv.lock`).
  Иначе — напрямую (`pytest`, `ruff`, `mypy`). Что используется — фиксируется в
  `.harness.conf` (`TEST_CMD`/`GATE_CMD`).
- **Зависимости — `pyproject.toml`** (современный) либо `requirements.txt` (legacy).
  Менять манифест зависимостей — только по явному запросу (см. `common/git.md`).
- **Docstring для публичного API** (модуль/класс/функция без `_`-префикса).
- **Не редактировать сгенерированное** — `__pycache__`, `*.egg-info`, vector store
  (`chroma_db`), кэши (`.mypy_cache`, `.ruff_cache`, `.pytest_cache`). Список —
  `READONLY_ZONES` в `.harness.conf`, guard блокирует (exit 2).

> Реестр найденных ловушек проекта — `.claude/docs/gotchas.md`.
