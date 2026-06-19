---
paths:
  - "**/*.vue"
  - "**/*.ts"
---

# @md/* библиотеки — как использовать

Приватные пакеты из JFrog (`@md:registry` в `.npmrc`, токен через `${NPM_TOKEN}`).
Ставить из реестра (точная версия / `^`), **НЕ** через `file:`/workspace-линк —
ломает `npm ci` в CI/Docker (нет соседнего репо).

**API смотреть в типах, не по памяти:** `node_modules/@md/<pkg>/dist/**/*.d.ts`
(ui-kit — `dist/types/`). README пакетов тонкие: список компонентов и пропсы там
НЕ описаны. Источник правды = типы установленной версии.

## Какая либа для чего
- **@md/ui-kit** — Vue 3 компоненты + Tailwind v4. Импорт компонента + один раз
  `@md/ui-kit/index.css`; приложение обернуть в `ThemeProvider`.
- **@md/auth** — Google OAuth **implicit token-флоу**: `GoogleStrategy`,
  `parseCallbackToken`/`validateCallbackState`, `createTokenStorage`/
  `createOAuthStateStorage`, `setupInterceptors` (Bearer), `createAuthMiddleware`.
  Все auth-примитивы брать ОТСЮДА.
- **@md/core** — в основном `createHttpClient({ API_BASE_URL })` → axios.
  Его `createGoogleParams`/`LoginCommand`/`Params` — ЛЕГАСИ code-флоу,
  для OAuth НЕ использовать (брать @md/auth).
- **@md/eslint-config** — flat ESLint 9: `@md/eslint-config/vue` и `/ts`.

## Стабильные gotchas (в типах не видно)
- **MdButton:** слот `#icon` рендерится ВСЕГДА первым; иконка «в конце» штатно
  не поддержана — компоновать внутри `#text`. `layout`: center=240px, full=w-full,
  auto=по контенту. `withIcon` → квадрат 48px (icon-only, текст не рендерится).
- **MdIcon:** `name` только из фикс-набора (logout/exit там НЕТ). Иконки вне набора →
  локальный реестр `src/shared/ui/icons`: svg только с `viewBox` (без `width/height`),
  `stroke="currentColor"` — иначе на мелком размере режется/не масштабируется.
- **@md/eslint-config (строгий, recommendedTypeChecked):** sync-функцию не делать
  `async` без `await` (и не `await` не-Promise); не ставить лишние type-assertion.
  В `eslint.config.js` задать `settings['better-tailwindcss'].entryPoint` (css c
  `@import "tailwindcss"`) и `parserOptions.projectService`; peer-плагины — у потребителя.

> Справочник компонентов ui-kit: `node_modules/@md/ui-kit/llms.txt` (авто-генерится
> в билде из типов, появляется с версии после 2.7.0). Фолбэк / детали типов — `dist/types/`.
