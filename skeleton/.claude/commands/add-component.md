# add-component

Создаёт структуру нового компонента по эталону пакета.

## Использование

```
/add-component <ComponentName>
```

## Что создаёт

```
<WATCH_DIR>/components/<component-name>/
  ui/
    <component-name>.vue
  model/
    types.ts
    const.ts
  lib/
    use<ComponentName>Classes.ts
    __tests__/
      use<ComponentName>Classes.spec.ts
  __tests__/
    <component-name>.spec.ts
  __stories__/
    <component-name>.stories.ts
  index.ts
```

## Шаги

1. Привести имя к kebab-case (`ComponentName` → `component-name`) и PascalCase
2. Создать все файлы по структуре выше
3. Заполнить `index.ts` barrel-экспортом
4. Добавить компонент в центральный реэкспорт пакета
5. Сообщить список созданных файлов

## Эталон структуры

`<REFERENCE_PATH>`

## Обязательно проверить после создания

- [ ] Barrel `index.ts` создан с именованным экспортом
- [ ] Компонент добавлен в центральный `index.ts` пакета
- [ ] Story создана в `__stories__/`
- [ ] Ревью по чеклисту: `@.claude/docs/REVIEW.md`
- [ ] Snapshot-тест создан в `__tests__/`
- [ ] Sensor запустил тесты — зелёные
