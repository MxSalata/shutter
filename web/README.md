# Shutter web application

The operator's and the approver's screens: the scenarios, the cases, and for each case its evidence, the board's findings, the plan with the gate's checks, the rehearsal, the approval, the dispatch and the verification; and the production review, a read-only pass over a production's settings and failures with an approver's annotations. It reads and writes only through Shutter's REST API (`/api/shutter`, `docs/CONTRACTS.md` section 5).

React, Mantine and TanStack Query, built with Vite. IRIS serves the build from `www/` at the repository root, at `/shutter/`; the setup creates that web application when `www/` exists.

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | The app on `http://localhost:5173`, with `/api/shutter` proxied to IRIS (`VITE_IRIS_URL`, default `http://192.168.0.10:52775`) |
| `VITE_MOCK=1 npm run dev` | The same against an in-browser mock of the API, which serves answers recorded from the real one (`src/mocks/fixtures.json`) |
| `npm test` | Unit and page tests (Vitest, jsdom, the same mock) |
| `npm run lint`, `npm run typecheck`, `npm run format:check` | ESLint, TypeScript and Prettier |
| `npm run build:www` | Builds into `../www/`, the folder IRIS serves (committed, so an install needs no Node) |
| `npm run build:demo`, `npm run preview:demo` | The demo, which is always the trial: recorded runs on the in-browser mock, opening signed in as the approver (`dist-demo/`, `VITE_BASE` for GitHub Pages) |
| `npm run record:demo -- --url http://host:52773` | Records the demo's data from a running Shutter's API into `src/mocks/fixtures.json` (reads only; `SHUTTER_PASSWORD` for the operator's password) |
| `npm run export:answers -- --url http://host:52774` | Exports the recorded answers to "Ask about this case" from a running Shutter's API into `src/mocks/recorded-questions.json` (reads only; `SHUTTER_PASSWORD` for the approver's password; the demo cases come from `fixtures.json`) |
| `npm run test:e2e` | Playwright, Chromium, two projects. `chromium`, on the demo build (always the trial): axe-core (WCAG 2.1 A and AA) on every screen, the trial's sign-in page and the guide open, in all five appearances; the layout at a phone's and a laptop's width; each page's paths, the guide's tours, and the public demo's role (`?as=demo`). `iris-trial`, on the build IRIS serves, previewed with no instance behind it: a visit to the trial from the live app sends nothing to IRIS (every call is recorded, and refused by the trial and by the browser), the trial never calls itself live, and the live sign-in page is audited |

## Notes

- Three appearances, light, dark and pastel, plus a high-contrast mode for light and dark, chosen in the appearance menu and remembered per browser; until a choice is made the app follows the system's settings. The colour tokens are tuned for 4.5:1 text contrast on every surface, which the accessibility test checks.

- The trial (the demo build, or `?trial` on the live app's address) opens the guide's welcome on a first visit, with three tours: the quick tour (Scenarios, an S2 case approved for you and played out to its verification, an S8 case with rules and the board side by side, an S20 case, the evaluation), a step or two on every screen, and one for integration engineers with Detail on Technical. `?trial=tour` and `?trial=engineer` open the first and the last from an address. Help in the header resumes it, starts it again or opens one chapter. Its steps are a typed registry (`src/features/guide/registry.ts`) pointing at `data-tour` attributes on the screens; a case step finds the newest case of its scenario and mode through the API. The guide only opens pages and sections, and its place is kept in localStorage (`shutter:guide:v2`) with nothing about cases or patients.
- The screens follow `GET /me`'s `can` (`operate`, `approve`, `configure`, `scenarios`, `docs/CONTRACTS.md` 5): without `scenarios` the Scenarios page offers no Run and no Reset and says the public demo plays its stories by itself; without `configure` the Site profile, the agent library and the production review's annotations are for reading, with a note where Save would be; a server that sends no `can` is read by the operator and approver flags, as before. While `GET /settings` carries `live: {enabled: true, every_minutes, last_played, next, ...}` (`docs/CONTRACTS.md` 4.4) a banner on every page says how often a new failure arrives, which story played last and which is due next. The mock shows this with `?as=demo` on the demo's address (`/?as=demo#/scenarios`): the trial then opens signed in as the public demo's role, which approves and cannot run, reset or save, and the settings carry a hospital feed (replayed). Keep `?as=demo` in every address you open by hand, since a page loaded without it starts the trial again as the approver.
- Times are shown in the feed's time zone and named ("15 Oct, 09:20:00 BST"); with Detail on Technical the UTC time sits beside them, and tooltips give UTC and the browser's own time.
- Routes are hash routes (`/shutter/#/cases/C-000011`): IRIS serves the files without rewriting unknown paths.
- Every change sends `X-Requested-With: Shutter`, and the idempotent ones an `Idempotency-Key` made per action. The keys come from `crypto.getRandomValues` when `randomUUID` is missing: IRIS serves the app over plain http, which is not a secure context.
- The build carries a Content-Security-Policy that allows only the app's own scripts and its own origin.
