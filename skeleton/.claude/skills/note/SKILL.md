---
name: note
description: "Быстро кинуть сырое наблюдение в буфер PENDING-NOTES.md без отрыва от работы. Разбирается позже в /end-session."
disable-model-invocation: true
argument-hint: "[текст заметки]"
---

!`bash "${CLAUDE_SKILL_DIR}/append.sh" "$ARGUMENTS"`

✓ Заметка в буфере. Разбор — в `/end-session`.
