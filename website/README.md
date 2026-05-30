# DarkCoW — showcase site

A single-page showcase for the **DarkCoW** hook: a privacy-preserving dark-pool
CoW hook for Uniswap v4, secured by an EigenLayer AVS with SP1 zero-knowledge
settlement. Built to make the project (and the skills behind it) legible to
recruiters at a glance.

**Stack:** Next.js (App Router) · TypeScript · Tailwind CSS · Framer Motion · Geist.
**Design:** "Dark Pool Depth" — near-black canvas, monospace technical labels,
a single mint-cyan accent, content that surfaces out of the dark on scroll.

## Develop

```bash
cd website
npm install
npm run dev          # http://localhost:3000
```

```bash
npm run build        # production build
npm run start        # serve the production build
npm run lint
```

## Where things live

```
app/                 layout (fonts, SEO, OG image), page composition, globals.css
components/          Hero, Problem, Overview, FlowWalkthrough, Pillars, Demo,
                     Skills, About, Footer + primitives (Section, Reveal, Figure,
                     CodePeek, Tag, Nav, DepthBackground)
content/site.ts      ← all copy + structured data lives here. Edit this first.
public/diagrams/     architecture / system-flow / execution-flow / verifying-flow PNGs
```

**To change copy, links, code snippets, skills, or the flow steps,** edit
`content/site.ts` — every section reads from it.

## Assets

The four diagrams are copied from the repo root into `public/diagrams/`:

| Source (repo root)     | Site path                          |
| ---------------------- | ---------------------------------- |
| `Architecture.png`     | `public/diagrams/architecture.png` |
| `hook/System_Flow.png` | `public/diagrams/system-flow.png`  |
| `Execution_Flow.png`   | `public/diagrams/execution-flow.png` |
| `Verifying_Flow.png`   | `public/diagrams/verifying-flow.png` |

The social/OG image is generated at build time from `app/opengraph-image.tsx`
(no binary asset to maintain). The favicon is `app/icon.svg`.

## Deploy (Vercel)

1. Push the repo to GitHub (already at `1Ayush-Petwal/Dark-Pool-hook`).
2. Import the project in Vercel and set the **Root Directory** to `website`.
3. Framework preset auto-detects Next.js. Deploy — add a custom domain if desired.

> The site is fully static-friendly. To host on GitHub Pages instead, add
> `output: "export"` to `next.config.ts` and serve the generated `out/`.

## TODO before launch

- Confirm / replace contact details in `content/site.ts` (`site.email`,
  and the optional `links.linkedin` / `links.x` / `links.resume`).
- Optionally set a real production `site.url` (used for OG + canonical).
