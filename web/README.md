# Interlock web application

The operator's and the approver's screens: the scenarios, the cases, and for each case its evidence, the board's findings, the plan with the gate's checks, the rehearsal, the approval, the dispatch and the verification. It reads and writes only through Interlock's REST API (`/api/interlock`, `docs/CONTRACTS.md` section 5).

React, Mantine and TanStack Query, built with Vite. IRIS serves the build from `www/` at the repository root, at `/interlock/`; the setup creates that web application when `www/` exists.

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | The app on `http://localhost:5173`, with `/api/interlock` proxied to IRIS (`VITE_IRIS_URL`, default `http://192.168.0.10:52775`) |
| `VITE_MOCK=1 npm run dev` | The same against an in-browser mock of the API, which serves answers recorded from the real one (`src/mocks/fixtures.json`) |
| `npm test` | Unit and page tests (Vitest, jsdom, the same mock) |
| `npm run lint`, `npm run typecheck`, `npm run format:check` | ESLint, TypeScript and Prettier |
| `npm run build:www` | Builds into `../www/`, the folder IRIS serves (committed, so an install needs no Node) |
| `npm run build:demo`, `npm run preview:demo` | The demo: recorded runs on the in-browser mock, with a "Try the demo" sign-in (`dist-demo/`, `VITE_BASE` for GitHub Pages) |
| `npm run record:demo -- --url http://host:52773` | Records the demo's data from a running Interlock's API into `src/mocks/fixtures.json` (reads only; `INTERLOCK_PASSWORD` for the operator's password) |
| `npm run test:e2e` | axe-core (WCAG 2.1 A and AA) on every screen of the demo in all five appearances (Playwright, Chromium) |

## Notes

- Three appearances, light, dark and pastel, plus a high-contrast mode for light and dark, chosen in the appearance menu and remembered per browser; until a choice is made the app follows the system's settings. The colour tokens are tuned for 4.5:1 text contrast on every surface, which the accessibility test checks.

- Times are shown in UTC, as the HL7 messages and the scenarios carry them; tooltips give the browser's own time.
- Routes are hash routes (`/interlock/#/cases/C-000011`): IRIS serves the files without rewriting unknown paths.
- Every change sends `X-Requested-With: Interlock`, and the idempotent ones an `Idempotency-Key` made per action. The keys come from `crypto.getRandomValues` when `randomUUID` is missing: IRIS serves the app over plain http, which is not a secure context.
- The build carries a Content-Security-Policy that allows only the app's own scripts and its own origin.
