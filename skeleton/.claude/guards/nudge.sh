#!/usr/bin/env bash
# UserPromptSubmit nudge — активирует пассивные прозовые правила (те, у которых нет скилла).
# Грепает промпт на триггеры → печатает ОДНУ строку-напоминание в stdout (Claude Code
# добавляет stdout UserPromptSubmit-хука в контекст). Nudge, не gate: exit 0 всегда, не
# блокирует. Граница (§6 judgment-layer): делает правило видимым в нужный момент, НЕ форсит
# правду суждения. /plan и /rename уже авто-инвокабельны (Рычаг-1) — их тут НЕ дублируем.
# context-hygiene завязан на состояние сессии, не на слова промпта — вне keyword-нуджа.
set -euo pipefail

input=$(cat)
if command -v jq >/dev/null 2>&1; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || printf '%s' "$input")
else
  # без jq — best-effort вытащить только .prompt (иначе cwd/пути в payload ложно матчат); фолбэк — raw
  prompt=$(printf '%s' "$input" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' || printf '%s' "$input")
fi

# Boundary-фича → verify-декларация (testing.md). Условно: молчим, если не матчит (токен-шум).
if printf '%s' "$prompt" | grep -qiE 'api|fetch|axios|endpoint|cors|\benv\b|\.env|backend'; then
  printf '%s\n' "↳ harness-nudge: похоже на boundary-фичу — перед «готово» объяви уровень verify: \`verified: real-runtime\` ИЛИ честный \`verified: tests-only\` (testing.md)."
fi

exit 0
