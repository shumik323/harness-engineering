#!/usr/bin/env bash
# Append-only capture: кидает сырую заметку в буфер PENDING-NOTES.md с timestamp.
# Вызывается из /note (SKILL.md) через инлайн-bash. Урок fenris: только append (>>),
# никаких strReplace — на больших буферах diff-инструмент таймаутит.
#
# Generic: путь буфера через CLAUDE_PROJECT_DIR (fallback на git root / pwd).

set -euo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
BUFFER="${REPO_ROOT}/.claude/PENDING-NOTES.md"

NOTE="${*:-}"
[[ -z "${NOTE// }" ]] && { echo "note: пустая заметка — пропущено" >&2; exit 0; }

mkdir -p "$(dirname "$BUFFER")"
if [[ ! -f "$BUFFER" ]]; then
  printf '# PENDING-NOTES — буфер наблюдений\n\n> Сырые заметки из /note. Разбираются в /end-session (triage → log/gotchas/decisions).\n> Префикс слоя опционален: [generic] → шаблон/обобщение, иначе → instance.\n\n' > "$BUFFER"
fi

printf -- '- [%s] %s\n' "$(date '+%Y-%m-%d %H:%M')" "$NOTE" >> "$BUFFER"
