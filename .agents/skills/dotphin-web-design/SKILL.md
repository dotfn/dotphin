---
name: dotphin-web-design
description: Design system for the Dotphin marketing site in web/ (Next.js). Load before touching any section, component or the drawn Dotphin window under web/src, before choosing any color, space, type or motion value there, and before calling any screen of the site finished. Wins over dotfn-taste when they disagree.
---

# Dotphin web — design system

Source of truth is the running code: tokens in `web/src/app/globals.css`, components in `web/src/components`, the drawn app window in `web/src/demo`. When this file and the code disagree and the code is right, fix this file in the same change.

## 1. Surfaces

One page, `/`, static export (`next build` → `web/out`). Visitors are Mac users deciding whether to install; they arrive once, so the page earns expression — but every claim must be true of the app today.

Sections, in order, each with an `id` the path bar walks (`web/src/lib/site.ts` → `sections`): `top` (hero), `features`, `views`, `terminal`, `shortcuts`, `compare`, `faq`, `get` (+ footer). Adding a section means adding it to `sections` too.

Structure is taken from this-day.app: centered hero with app icon, a single pill link, two-tone headline, product shown as live UI rather than screenshots, a floating glass bar at the bottom naming the current section, comparison table, FAQ, closing CTA.

## 2. Brand gesture

**The path bar.** Dotphin's breadcrumb, turned into page navigation: `Dotphin › Section` with prev/next and a download button, floating in glass at the bottom. It's the only always-visible chrome. Don't add a top nav.

**Water.** The hero stage is the only place the WebGL water (`WaterCanvas`) appears — teal folds with one warm glossy shape (from the Payrix dribbble shot). One per page; a second WebGL canvas needs a reason.

## 3. Color

Roles only — never a raw hex in a component. Page roles: `--bg`, `--bg-sunk`, `--surface`, `--ink`, `--ink-2`, `--ink-3`, `--accent`. Drawn-window roles: `--mac-ink`, `--mac-ink-2`, `--mac-ink-3`. Git: `--git-*`. Terminal: `--term-*`. Water (`--water-*`, `--sun`) is illustration only — never text, never a control.

- Text on `--bg`/`--surface` is ≥4.5:1. `--ink-3` is 3.4:1 and is only for display text ≥24px (the gray second line of the hero/closing headlines).
- `--accent` is the one action/selection color: primary buttons, the focused-pane dot, selection, links.
- Git status is always a letter in a badge (M, A, ?, D) plus a screen-reader label; color never carries it alone. Badge fills are ≥5:1 against white.
- Light only. The terminal block is dark because terminals are; that's not a dark mode.

## 4. Type

- **Urbanist** (`--font-sans`): all page copy. Body 17px/1.5; section headings `clamp(34px,5vw,52px)` bold, tracking −0.03em; hero `clamp(44px,8vw,84px)`.
- **System UI** (`--font-mac`, `font-mac` class): inside the drawn Dotphin window and the feature mini-UIs, at 12–13px — it's a picture of a macOS app, so it uses the Mac's face and sizes. Never below 12px.
- **Geist Mono** (`--font-mono`): the terminal and the brew command.
- Compared numbers (sizes, counts) use `.tabular`.

## 5. Space, shape, depth

- Spacing on a 4px grid; section top padding `pt-28 sm:pt-36`; content widths 720 (text), 920–1080 (sections), 1180–1280 (stages).
- Radii: page cards 28px with 20px inner wells (nested radius shrinks); stages 28/36px; buttons 14px; chips/pills full. The drawn window is 22px.
- Shadows only on things that float: the drawn window (`--shadow-window`), the path bar and its menu (`--shadow-float`). Page cards are flat on the page — no shadow, no border.
- Glass (`.glass`, `.glass-strong`) is for floating chrome only.

## 6. Motion

Measured on this-day.app: `--ease-out: cubic-bezier(0,0,.2,1)`, `--ease-spring: cubic-bezier(.34,1.36,.64,1)`, durations 180 / 280 / 380ms (`--dur-quick/standard/insert`).

- **One crafted moment**: the hero window lies back on the water (rotateX 26°, scale .9) and stands up as the stage scrolls in (`motion` `useScroll`).
- Demos play scripts only while on screen (`useScriptedDemo`), loop after a hold, and show their end state still under reduced motion.
- Path bar title crossfades 280ms; its menu grows from the trigger and exits faster than it enters.
- No fade-and-rise on sections. No marquees, no pulsing dots.
- Reduced motion: global CSS kills transitions/animations; JS demos jump to their final frame; the water renders one frame.

## 7. Navigation

Path bar fixed bottom-center on every size; `●fn` (bottom-left) and GitHub (bottom-right) only from `lg`. Primary action is "Download for Mac" (latest GitHub release) with the Homebrew command beside it.

## 8. The demo window (future playground)

`web/src/demo` is built to become interactive without rewriting views:

- `fs.ts` — the fake home folder. `state.ts` — `DemoState` + `reduce(state, action)`; every behavior is an `Action`.
- `DotphinWindow` renders state only. With `dispatch` it becomes live (`role="application"`), without it it's a picture (`role="img"` + a one-sentence label).
- `player.ts` — scripted demos dispatch the same actions on a timer. Interactivity = dispatch from real input instead.
- `ViewModes` is the first live piece: a real control dispatching `setViewMode`.

When adding a feature to the demo: add the `Action`, handle it in `reduce`, render it in the views. Never put behavior in a view.

## 9. Focus, keyboard, touch

Global `:focus-visible` ring in `--accent`, 2px, offset 3. Hit areas ≥44px under `sm`, ≥24px with a pointer (`h-11 sm:h-9` pattern). Zoom never disabled.

## 10. Writing

English, plain, second person. Name keys with the Mac glyphs (⌘ ⇧ ⌃ ⌥) and `Kbd`. Every shortcut on the page is read from `Sources/Dotphin/App/FileEditCommands.swift` — check there before adding one. Every feature claim must exist in `Sources/`. Facts live in `web/src/lib/site.ts`.

The page says "not notarized yet" plainly; it never claims "open source" (no license is chosen) and never says anything negative about Finder beyond the table.

## 11. Rejected on sight

- Stat tiles in boxes — the three facts under the hero are unboxed, and the figures are keys (⌘\, ⌃`) or a real zero.
- Icon-in-tinted-square feature rows — feature cards lead with a working fragment of the app instead; the "details" list is text only.
- A drawn browser/phone frame around the window — the window *is* the product.
- Eyebrow labels over headings — the hero pill is the only one.

## 12. Known traps

- Grid children holding the mini-UIs need `min-w-0`, or the cards overflow at 390px (caught by the audit).
- A bulk find-and-replace of hex values also rewrites the token definitions in `globals.css` into `var(--x): var(--x)` — exclude that file.
- `react-hooks/set-state-in-effect` rejects reading `matchMedia` into state in an effect; use `motion`'s `useReducedMotion`.
- The seed folders are sorted through `sortEntries` at load so items copied in later don't reshuffle the list mid-demo.
- This Next.js (16.4) differs from training data — read `web/node_modules/next/dist/docs/` before using a new API.

## 13. Still open

- Production domain (`site.url` is an assumption) and hosting.
- Spanish version (the app ships en/es; the page is English only, with copy in components).
- Social preview image is the README screenshot (dark, 1271×810) — a designed 1200×630 card would be better.
- Whether the closing CTA should get the water too.

## 14. Before calling it done

Run from `web/`: `npm run build`, serve `out/`, then
`node ../.agents/skills/dotfn-audit/scripts/audit.mjs --url <server> --routes / --viewports 390x844,1440x900 --min-text 12`.
Known, accepted: "control contrast — no visible boundary" on the path bar's icon-only buttons (the icon itself is ~15:1 on the glass; WCAG 1.4.11 is about the graphic). Then look at the screenshots — the hero mid-script (≈8s after it scrolls in) and the keyboard section are the ones a rule can't judge.
