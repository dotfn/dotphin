# Dotphin website

The marketing site for Dotphin. Next.js 16 (App Router) as a static export, Tailwind CSS 4, `motion` for scroll and UI motion, `three` for the hero's water shader.

```sh
npm install
npm run dev      # http://localhost:3000
npm run build    # static site in out/
```

`out/` is plain HTML/CSS/JS — host it anywhere (GitHub Pages, Cloudflare Pages, Vercel).

## Layout

```
src/app/            layout, page, global tokens (globals.css)
src/components/     page sections, path bar, water canvas
src/demo/           the Dotphin window drawn in HTML
  fs.ts             fake home folder
  state.ts          DemoState + reduce(state, action)
  player.ts         scripted demos (dispatch actions on a timer)
  DotphinWindow.tsx renders state; optional dispatch makes it live
src/lib/site.ts     product facts, links, section list
```

## Toward the playground

The demo window is already a state machine: every behavior is an `Action` handled in `reduce`, and the views only render state. Scripted demos and the one live control (view modes) dispatch the same actions. Making the window interactive means wiring clicks and keys to `dispatch` — not rewriting the views.

## Design rules

`../.agents/skills/dotphin-web-design/SKILL.md` — tokens, type, motion, what's been rejected, and the audit to run before shipping.
