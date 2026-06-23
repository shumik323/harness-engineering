#!/usr/bin/env bash
# Пути CORE-слоя относительно корня инстанса. Только это синкается.
CORE_PATHS=(
  ".claude/guards/block-zones.sh"
  ".claude/guards/gate.sh"
  ".claude/guards/run-test-hook.sh"
  ".claude/guards/nudge.sh"
  ".claude/skills/note/append.sh"
  ".claude/skills/note/SKILL.md"
  ".claude/skills/end-session/SKILL.md"
  ".claude/skills/task/SKILL.md"
  ".claude/skills/plan/SKILL.md"
  ".claude/skills/rename/SKILL.md"
  ".claude/rules/common/git.md"
  ".claude/rules/common/testing.md"
  ".claude/rules/common/workflow.md"
  ".claude/rules/common/methodology-routing.md"
  ".claude/rules/common/context-hygiene.md"
)
