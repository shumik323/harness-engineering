#!/usr/bin/env bash
# UserPromptSubmit nudge — активирует пассивные прозовые правила (те, у которых нет скилла).
# Грепает промпт на триггеры → печатает ОДНУ строку-напоминание в stdout (Claude Code
# добавляет stdout UserPromptSubmit-хука в контекст). Nudge, не gate: exit 0 всегда, не
# блокирует. Граница (§6 judgment-layer): делает правило видимым в нужный момент, НЕ форсит
# правду суждения. /plan и /rename уже авто-инвокабельны (Рычаг-1) — их тут НЕ дублируем.
# context-hygiene завязан на состояние сессии, не на слова промпта — вне keyword-нуджа.
# Исключение из «/plan не дублируем»: трек A (фича) сам не стартует — агент забывает, что он
# состоит из шагов. Нудж зовёт /feature, а шаги ведёт скил.
# Конфиг (.harness.conf, опц.): TICKET_PATTERN — ERE номера тикета ("MD-[0-9]+"). Пусто или нет
# → ветка по тикету молчит. Значение читается строкой, не через source: stdout этого события
# уходит в контекст модели, исполненный конфиг мог бы напечатать туда лишнее.
set -euo pipefail

input=$(cat)
if command -v jq >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || printf '%s' "$input")
else
  # без jq — best-effort вытащить только .prompt (иначе cwd/пути в payload ложно матчат); фолбэк — raw
  prompt=$(printf '%s' "$input" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' || printf '%s' "$input")
fi

# Фича (трек A) → зови /feature. Корни слов без окончаний: «фич» ловит фича/фичу/фичи.
# Без `\b` у кириллицы: в C-локали (хук без LANG) граница слова по байтам не работает.
FEATURE_RE='фич|Фич|feature|нов(ый|ого|ому|ым) срез|макет|figma'
CONF="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.harness.conf"
ticket_re=""
if [[ -f "$CONF" ]]; then
  line=$(grep -E '^TICKET_PATTERN=' "$CONF" | tail -n1 || true)
  ticket_re="${line#TICKET_PATTERN=}"
  ticket_re="${ticket_re#[\"\']}"
  ticket_re="${ticket_re%[\"\']}"
fi
if printf '%s' "$prompt" | grep -qiE "$FEATURE_RE" \
   || { [[ -n "$ticket_re" ]] && printf '%s' "$prompt" | grep -qE -- "$ticket_re" 2>/dev/null; }; then
  printf '%s\n' "↳ harness-nudge: похоже на фичу (трек A) — зови /feature"
fi

# Boundary-фича → verify-декларация (testing.md). Условно: молчим, если не матчит (токен-шум).
if printf '%s' "$prompt" | grep -qiE 'api|fetch|axios|endpoint|cors|\benv\b|\.env|backend'; then
  printf '%s\n' "↳ harness-nudge: похоже на boundary-фичу — перед «готово» объяви уровень verify: \`verified: real-runtime\` ИЛИ честный \`verified: tests-only\` (testing.md)."
fi

exit 0
