# Language pack: Vue / component-library

Образцовый **языковой пакет** поверх абстрактного ядра skeleton. Показывает, как
расширять харнес под конкретный стек, не трогая generic-слой.

## Что внутри

```
lang-packs/vue/
├── skills/
│   └── add-component/SKILL.md   ← скаффолдинг Vue-компонента (/add-component)
└── docs/
    ├── dev-guide.md.template    ← как добавить компонент (Vue-флоу)
    └── REVIEW-vue.md.template   ← Vue-специфичный чеклист ревью
```

Правила Vue (что грузится агенту автоматически на `*.vue`) лежат отдельно —
`skeleton/.claude/rules/lang/vue.md` (path-scoped).

## Как подключить

Vue-проект = ядро skeleton **плюс** этот пакет:

```bash
# 1. Скопировать ядро
cp -r skeleton/.claude ./
cp skeleton/.harness.conf.example ./.harness.conf

# 2. Наложить Vue-пакет
cp -r skeleton/lang-packs/vue/skills/add-component ./.claude/skills/
cp skeleton/lang-packs/vue/docs/*.template ./.claude/docs/
#    rules/lang/vue.md уже в ядре — оставить, удалить go.md/php.md если не нужны
```

Не-Vue стек (Go, PHP, …) — этот пакет не копируешь, берёшь/пишешь свой
(`rules/lang/<lang>.md` уже даёт точку старта).
