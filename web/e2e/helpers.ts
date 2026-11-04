import { expect, type Page } from '@playwright/test';

/** How a page is opened: as the public demo's role (`?as=demo`), and with the Detail switch on Technical. */
export interface Opened {
  as?: 'demo';
  detail?: 'technical';
}

/**
 * Opens a page of the app. The address keeps the same query in every step of a test: a navigation that changes it
 * reloads the page, and the trial starts afresh from the recording (signed in again as the role the address names).
 */
export function go(page: Page, path: string, opened: Opened = {}) {
  const query = [
    ...(opened.as ? [`as=${opened.as}`] : []),
    ...(opened.detail ? [`detail=${opened.detail}`] : []),
  ].join('&');
  return page.goto(`./${query ? `?${query}` : ''}#${path}`);
}

/**
 * The demo build is always the trial and opens signed in: as the approver of the recorded runs, or (`as: 'demo'`)
 * as the live hospital's public role, who approves but cannot run or reset scenarios or save the site. This opens
 * Scenarios and waits until it is there.
 */
export async function signIn(page: Page, opened: Opened = {}) {
  await go(page, '/scenarios', opened);
  await expect(page.getByRole('heading', { name: 'Scenarios', exact: true })).toBeVisible();
}

/** Signs the trial's user out, to the trial's own sign-in page (its roles, no password). */
export async function signOutOfTrial(page: Page) {
  await page.getByRole('button', { name: /^Signed in as / }).click();
  await page.getByRole('menuitem', { name: 'Sign out' }).click();
  await expect(
    page.getByRole('heading', { name: 'Choose who you are in the trial', level: 1 }),
  ).toBeVisible();
}

/**
 * Opens every closed story step of a case page, and its Outcome band when it is closed (a closed case's starts so), and
 * waits for the panels to finish opening: a closed step is hidden, and a check of the page would skip it.
 */
export async function openSteps(page: Page) {
  const band = page.getByRole('button', { name: 'Outcome', exact: true, expanded: false });
  if (await band.count()) await band.click();
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

/**
 * The hospital feed's banner, which the public demo's role sees on every page: "Mikolaj's Fictional Hospital, live" on a live page,
 * and "Mikolaj's Fictional Hospital, replayed" in the trial, which the demo build always is.
 */
export const banner = (page: Page) =>
  page.getByRole('region', { name: /^Mikolaj's Fictional Hospital, (live|replayed)$/ });

/** The note that stands where Save would be for the public demo's role. */
export const READ_ONLY = /On the online demo you can approve or reject plans; a site's approver saves changes here/;

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
  /**
   * A window width of its own, for a state that exists only there (Ask open as a drawer at 1280, beside the case at
   * 1440): axe audits it at that width, and the layout run checks it at that width instead of 360 and 1024 px.
   */
  width?: number;
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

/** A screen's test name: its heading, the state its address names, whether every step is open, its Detail and width. */
export function screenName(screen: Screen): string {
  const base =
    screen.name ??
    (screen.path.includes('?') ? `${screen.heading} (${screen.path.split('?')[1]})` : screen.heading);
  return `${base}${screen.steps ? ', every step open' : ''}${screen.detail ? ', Technical' : ''}${
    screen.width ? `, at ${screen.width} px` : ''
  }`;
}

/** Sets the window to a screen's own width, when it has one (800 px high, as the layout run's windows are). */
export async function atWidth(page: Page, screen: Screen) {
  if (screen.width) await page.setViewportSize({ width: screen.width, height: 800 });
}
