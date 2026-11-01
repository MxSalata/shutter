import { expect, type Page } from '@playwright/test';

/** How a page is opened: as the public demo's role (`?as=demo`), and with the Detail switch on Technical. */
export interface Opened {
  as?: 'demo';
  detail?: 'technical';
}

/**
 * Opens a page of the app. The address keeps the same query in every step of a test: a navigation that changes it
 * reloads the page, and the demo's mock forgets who is signed in.
 */
export function go(page: Page, path: string, opened: Opened = {}) {
  const query = [
    ...(opened.as ? [`as=${opened.as}`] : []),
    ...(opened.detail ? [`detail=${opened.detail}`] : []),
  ].join('&');
  return page.goto(`./${query ? `?${query}` : ''}#${path}`);
}

/**
 * Signs in with the demo's own sign-in: as the approver of the recorded runs, or (`as: 'demo'`) as the live
 * hospital's public role, who approves but cannot run or reset scenarios or save the site.
 */
export async function signIn(page: Page, opened: Opened = {}) {
  await go(page, '/login', opened);
  await page
    .getByRole('button', { name: opened.as === 'demo' ? /^Try the demo \(live hospital/ : /Try the demo/ })
    .click();
  await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
}

/**
 * Opens every closed story step of a case page and waits for the panels to finish opening: a closed step is hidden,
 * and a check of the page would skip it.
 */
export async function openSteps(page: Page) {
  for (const step of await page.getByRole('button', { name: /^\d\. / }).all())
    if ((await step.getAttribute('aria-expanded')) !== 'true') await step.click();
  await expect(page.getByRole('button', { name: /^\d\. /, expanded: false })).toHaveCount(0);
  await expect(page.getByRole('status')).toHaveCount(0);
  // The panels' opening transitions, not an endless one such as a progress bar's stripes
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every((a) => a.playState !== 'running' || a.effect?.getTiming().iterations === Infinity),
  );
}

/** The live hospital's banner, which the public demo's role sees on every page. */
export const banner = (page: Page) => page.getByRole('region', { name: 'Live hospital' });

/** The note that stands where Save would be for the public demo's role. */
export const READ_ONLY = /The public demo is read-only: a site's approver saves changes here/;

/** One screen that the accessibility and layout runs check. */
export interface Screen {
  /** The address after the `#`, with the page's own query. */
  path: string;
  /** The page's h1, whose appearance says the page has loaded. */
  heading: string;
  /** Open every closed story step of a case page first. */
  steps?: 'open';
  /** The test's name, where the path alone would not say which state it is. */
  name?: string;
  /** Which runs check it: axe in all five appearances (`a11y`), the width at 360 and 1024 px (`layout`). Both if unset. */
  checks?: ('a11y' | 'layout')[];
  /** Opened with the Detail switch on Technical. */
  detail?: 'technical';
}

/** One area of the app, as one page package owns it: its tag for `--grep`, and the screens the shared runs check. */
export interface Area {
  /** `@<area>`, appended to the title of every shared test of the area. */
  tag: `@${string}`;
  /** Screens of the demo build, signed in as the approver of the recorded runs. */
  screens: Screen[];
  /** Screens as the live hospital's public role sees them (`?as=demo`), checked by axe in all five appearances. */
  liveScreens?: Screen[];
  /** Live pages the IRIS build's trial project audits (the live sign-in page). */
  irisScreens?: Screen[];
  /** True once no visible text in the area's trial pages says "live" outside the allowed phrases. */
  liveWordChecked: boolean;
}

/** Whether a run checks a screen. */
export const checkedBy = (screen: Screen, run: 'a11y' | 'layout') =>
  !screen.checks || screen.checks.includes(run);

/** A screen's test name: its heading, the state its address names, whether every step is open, and its Detail. */
export function screenName(screen: Screen): string {
  const base =
    screen.name ??
    (screen.path.includes('?') ? `${screen.heading} (${screen.path.split('?')[1]})` : screen.heading);
  return `${base}${screen.steps ? ', every step open' : ''}${screen.detail ? ', Technical' : ''}`;
}
