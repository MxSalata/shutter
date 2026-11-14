import { expect, test, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { GUIDE_KEY, skipWelcome } from './guide';
import { areas, shell, signIn as signInArea } from './areas';
import { checkedBy, screenName, type Screen } from './helpers';

/**
 * The trial on the build IRIS serves (the `iris-trial` project: previewed at /shutter/ with no proxy, and an instance
 * address nothing listens on). Every test also answers `/api/shutter` in the browser with a stub (the live page's
 * GET /me is 401, GET /health a small live report) and records each hit with the phase it came in, so the proof is
 * that a trial page never sends one: its calls are answered by the recorded mock in the page itself, and the page's
 * own policy (`connect-src 'none'`) makes the browser refuse any that tried.
 */

interface Hit {
  phase: 'live' | 'trial';
  method: string;
  path: string;
}

/** The stand-in for a live instance: a person not signed in, and a healthy live report. */
async function stubInstance(page: Page) {
  const hits: Hit[] = [];
  const state = { phase: 'live' as Hit['phase'] };
  await page.route('**/api/shutter/**', (route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    hits.push({ phase: state.phase, method: request.method(), path });
    if (path.endsWith('/me'))
      return route.fulfill({ status: 401, json: { error: 'unauthorized', detail: 'Not signed in' } });
    if (path.endsWith('/health'))
      return route.fulfill({ json: { ok: true, demo: false, version: 'stub', checks: [] } });
    return route.fulfill({ status: 404, json: { error: 'not_found', detail: 'Not on the stub' } });
  });
  return {
    hits,
    trial: () => hits.filter((h) => h.phase === 'trial'),
    enter: () => (state.phase = 'trial'),
    leave: () => (state.phase = 'live'),
  };
}

/** What the trial's journal holds: the calls answered in the page, and what was refused. */
const journal = (page: Page) =>
  page.evaluate(() => {
    const j = window.shutterTrial?.journal;
    return j ? { ...j.counts(), calls: j.entries().length } : null;
  });

/** The live page of the IRIS build: its sign-in page, since the stub says nobody is signed in. */
async function openLive(page: Page) {
  await page.goto('./#/login');
  await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
  // Its own calls settled, so none of them can be counted against the trial that follows
  await page.waitForLoadState('networkidle');
}

/** A trial page at this address, signed in as the trial's approver from the start. */
async function openTrial(page: Page, path = '/scenarios', query = 'trial') {
  await page.goto(`./?${query}#${path}`);
  await expect(page.getByRole('region', { name: 'Trial environment' })).toBeVisible();
}

/** The held S2 case, approved in the trial through its own Approve the resend and the confirm. */
async function approveHeldCase(page: Page, query = 'trial') {
  await page.goto(`./?${query}#/cases/C-000002?open=decision`);
  const approve = page.locator('[data-tour-action="approve-plan"]');
  await expect(approve).toBeEnabled();
  await approve.click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: /^Approve/ }).click();
  await expect(approve).toHaveCount(0);
}

test.describe('the trial on the build IRIS serves', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test('sends nothing to IRIS through a whole visit: the quick tour, an approval, a run and every page', async ({
    page,
  }) => {
    const stub = await stubInstance(page);
    const refusals: string[] = [];
    page.on('console', (m) => {
      if (/Content Security Policy|Refused to connect/i.test(m.text())) refusals.push(m.text());
    });
    await openLive(page);
    expect(stub.hits.some((h) => h.path.endsWith('/me'))).toBe(true);

    // The guided tour's address, as the sign-in page's and Help's links open it
    stub.enter();
    await page.goto('./?trial=tour#/scenarios');
    await expect(page.getByRole('region', { name: 'Trial environment' })).toBeVisible();
    // The address is normalised to ?trial, so a reload does not start the tour again
    await expect(page).toHaveURL(/\/shutter\/\?trial#\/scenarios$/);
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toBeHidden();

    // The quick tour starts by itself, Next by Next: the guide approves the held S2 case for the reader on its decision step
    const guide = page.getByRole('region', { name: 'Guide' });
    for (let n = 1; n <= 9; n++) {
      await expect(guide).toContainText(`Step ${n} of 9`);
      await guide.getByRole('button', { name: n === 9 ? 'Finish' : 'Next' }).click();
    }
    await expect(page.getByRole('region', { name: 'Guide' })).toContainText('That is the tour.');

    // Run a scenario
    await page.goto('./?trial#/scenarios');
    const before = (await journal(page))!.actions;
    await page.locator('[data-tour-action="run-S2"]').first().click();
    await expect.poll(async () => (await journal(page))!.actions).toBeGreaterThan(before);

    // Every other page
    for (const [path, heading] of [
      ['/cases', 'Cases'],
      ['/incidents', 'Incidents'],
      ['/reviews', 'Production review'],
      ['/site-profile', 'Site profile'],
      ['/library', 'Agent library'],
      ['/settings', 'Settings and costs'],
      ['/evaluation', 'Evaluation'],
      ['/health', 'Health'],
    ]) {
      await page.goto(`./?trial#${path}`);
      await expect(page.getByRole('heading', { name: heading, exact: true })).toBeVisible();
    }

    expect(stub.trial()).toEqual([]);
    expect(refusals).toEqual([]);
    const j = await journal(page);
    expect(j).toMatchObject({ refused: 0, violations: 0 });
    expect(j!.reads).toBeGreaterThan(10);
  });

  test("refuses a call from the page's console: the guard, and the browser's own policy", async ({
    page,
  }) => {
    const stub = await stubInstance(page);
    const refusals: string[] = [];
    page.on('console', (m) => {
      if (/Content Security Policy|Refused to connect/i.test(m.text())) refusals.push(m.text());
    });
    stub.enter();
    await openTrial(page);
    expect(
      await page.evaluate(() =>
        fetch('/api/shutter/me').then(
          () => 'sent',
          () => 'refused',
        ),
      ),
    ).toBe('refused');
    // A request that goes round the guard is refused by the browser itself
    expect(
      await page.evaluate(
        () =>
          new Promise<string>((resolve) => {
            const x = new XMLHttpRequest();
            x.onload = () => resolve('sent');
            x.onerror = () => resolve('refused');
            try {
              x.open('GET', '/api/shutter/me');
              x.send();
            } catch {
              resolve('refused');
            }
          }),
      ),
    ).toBe('refused');
    await expect.poll(() => journal(page)).toMatchObject({ refused: 1 });
    await expect.poll(async () => (await journal(page))!.violations).toBeGreaterThan(0);
    expect(refusals.length).toBeGreaterThan(0);
    expect(stub.trial()).toEqual([]);
  });

  test('leaves for the live app as it was: no banner, no frame, its own session asked again', async ({
    page,
  }) => {
    const stub = await stubInstance(page);
    stub.enter();
    // The welcome of a first entry would cover the case page
    await skipWelcome(page);
    await approveHeldCase(page);
    await page
      .getByRole('region', { name: 'Trial environment' })
      .getByRole('button', { name: 'Leave trial' })
      .click();
    const dialog = page.getByRole('dialog', { name: 'Leave the trial?' });
    await expect(dialog).toContainText(
      'What you did here is discarded. Nothing was sent to a hospital system or IRIS.',
    );
    stub.leave();
    await dialog.getByRole('button', { name: 'Leave trial' }).click();
    await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
    expect(new URL(page.url()).search).toBe('');
    await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
    expect(await page.evaluate(() => document.documentElement.dataset.shutterEnv)).toBeUndefined();
    expect(await page.evaluate(() => getComputedStyle(document.body, '::after').borderTopWidth)).not.toBe(
      '3px',
    );
    await expect(page.getByText('You are back in the live system. Actions here are real.')).toBeVisible();
    await expect(page).toHaveTitle(/^(?!.*\(trial\))/);
    // The live app asked its own instance who is signed in; nothing of the trial's approval went anywhere
    expect(stub.hits.filter((h) => h.phase === 'live').map((h) => `${h.method} ${h.path}`)).toContain(
      'GET /api/shutter/me',
    );
    expect(stub.hits.some((h) => h.method !== 'GET')).toBe(false);
    expect(stub.trial()).toEqual([]);
  });

  test("offers Leave trial in the user menu and the tour's menu, where a live system waits", async ({
    page,
  }) => {
    const stub = await stubInstance(page);
    stub.enter();
    await skipWelcome(page);
    await openTrial(page);
    await page.getByRole('button', { name: /^Signed in as approver/ }).click();
    const user = page.getByRole('menu', { name: /^Signed in as approver/ });
    await expect(user.getByRole('menuitem', { name: 'Leave trial' })).toBeVisible();
    await expect(page.getByTestId('trial-only-note')).toHaveCount(0);
    await page.getByRole('button', { name: /^Signed in as approver/ }).click();
    await expect(user).toBeHidden();
    await page.getByRole('button', { name: 'Tour' }).click();
    await expect(
      page.getByRole('menu', { name: 'Tour' }).getByRole('menuitem', { name: 'Leave trial' }),
    ).toBeVisible();
    await expect(page.getByTestId('trial-only-note')).toHaveCount(0);
    expect(stub.trial()).toEqual([]);
  });

  test('starts afresh on a reload, as the same role, with the guide where it was', async ({ page }) => {
    const stub = await stubInstance(page);
    stub.enter();
    await skipWelcome(page);
    await openTrial(page);
    await page.getByRole('button', { name: /^Signed in as approver/ }).click();
    await page.getByRole('menuitem', { name: 'Operator' }).click();
    await expect(page.getByRole('button', { name: 'Signed in as operator (trial user)' })).toBeVisible();
    await page.reload();
    await expect(page.getByRole('region', { name: 'Trial environment' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Signed in as operator (trial user)' })).toBeVisible();
    const progress = await page.evaluate((key) => localStorage.getItem(key), GUIDE_KEY);
    expect(progress).not.toBeNull();
    // The welcome stays closed: the guide's place is on the device, not in the trial's memory
    await expect(page.getByRole('dialog', { name: 'Welcome to the Shutter trial' })).toHaveCount(0);
    // As the approver, the held case waits once more after a reload: the trial's changes reset with the page
    await approveHeldCase(page, 'trial&as=approver');
    await page.reload();
    await expect(page.locator('[data-tour-action="approve-plan"]')).toBeEnabled();
    expect(stub.trial()).toEqual([]);
  });

  test("goes Back from the trial's first page to the live sign-in page, without the banner", async ({
    page,
  }) => {
    const stub = await stubInstance(page);
    await openLive(page);
    stub.enter();
    await skipWelcome(page);
    await openTrial(page);
    stub.leave();
    await page.goBack();
    await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
    await expect(page.getByRole('region', { name: 'Trial environment' })).toHaveCount(0);
    await expect(page.getByText('You are back in the live system. Actions here are real.')).toBeVisible();
    expect(stub.trial()).toEqual([]);
  });

  test('keeps the trial out of a live page: no trial script, no recording', async ({ page }) => {
    await stubInstance(page);
    const scripts: string[] = [];
    page.on('response', (r) => {
      if (r.request().resourceType() === 'script') scripts.push(new URL(r.url()).pathname);
    });
    await openLive(page);
    await page.waitForLoadState('networkidle');
    expect(scripts.filter((s) => /trial/i.test(s))).toEqual([]);
    const bodies = await page.evaluate(async (paths) => {
      // The page's own scripts, read again from the same origin (not the API)
      const texts = await Promise.all(paths.map((p) => fetch(p).then((r) => r.text())));
      return texts.map((t, i) => ({
        path: paths[i],
        size: new TextEncoder().encode(t).length,
        // A line only the recordings carry (fixtures.json's source)
        recording: t.includes('on an instance with IRIS AI Hub at 2026-11-02T14:56:18Z'),
      }));
    }, scripts);
    expect(bodies.filter((b) => b.recording)).toEqual([]);
    // The entry stays within about 5 KB of the build before the trial (69,373 bytes at ddb9c08); 1.4.3 added 280 bytes
    // of lazy-chunk dependency lists for the shared locked Save and the judges' rights, and 1.4.5's items 234 bytes, the shell's
    // bounded failed count among them, and 1.4.6's merged items 34 more and the site profile's
    // Ask Shutter about this, in the shell's Ask panel, 558 more, so the allowance is 6,400 bytes
    const src = await page.evaluate(
      () => new URL(document.querySelector<HTMLScriptElement>('script[type="module"][src]')!.src).pathname,
    );
    const entry = bodies.find((b) => b.path === src);
    expect(entry, 'the entry chunk').toBeTruthy();
    expect(entry!.size).toBeLessThanOrEqual(69_373 + 6_400);
  });
});

/**
 * "Live" inside the trial (DESIGN.md 1.3, N7): with Detail on Plain, no visible text of a trial page says "live"
 * except "live system" and the Leave trial control. A name is data, not the trial's words: "Live PAS", the hospital
 * production's item that the recorded review of it finds disabled. Each area turns its check on (`liveWordChecked`)
 * once its pages are written in the trial's words.
 */
const LIVE_ALLOWED = /\blive system\b|\bLive PAS\b/gi;

async function liveWords(page: Page, scope: 'shell' | 'page'): Promise<string[]> {
  return page.evaluate(
    ({ scope, allowed }) => {
      const parts =
        scope === 'shell'
          ? [...document.querySelectorAll<HTMLElement>('header, nav, [data-testid="live-banner"]')]
          : [document.body];
      const text = parts.map((p) => p.innerText).join('\n');
      return text
        .split('\n')
        .map((line) => line.replace(new RegExp(allowed, 'gi'), ''))
        .filter((line) => /\blive\b/i.test(line));
    },
    { scope, allowed: LIVE_ALLOWED.source },
  );
}

test.describe('the trial never calls itself live', () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test(`the shell's words ${shell.tag}`, async ({ page }) => {
    await stubInstance(page);
    await skipWelcome(page);
    for (const as of ['approver', 'demo']) {
      await openTrial(page, '/scenarios', `trial&as=${as}`);
      expect(await liveWords(page, 'shell')).toEqual([]);
    }
  });

  for (const area of areas.filter((a) => a.liveWordChecked && a.screens.length))
    test(`every page's words ${area.tag}`, async ({ page }) => {
      await stubInstance(page);
      await skipWelcome(page);
      for (const screen of area.screens.filter((s) => !s.detail)) await checkScreen(page, screen);
    });
});

async function checkScreen(page: Page, screen: Screen) {
  await openTrial(page, screen.path);
  await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
  await expect(page.getByRole('status')).toHaveCount(0);
  expect(await liveWords(page, 'page'), screenName(screen)).toEqual([]);
}

/** The live sign-in page, which only a build IRIS serves has, in every appearance; and the areas' other live pages. */
for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility of the live pages (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test(`the live sign-in page ${signInArea.tag}`, async ({ page }) => {
      await stubInstance(page);
      await openLive(page);
      expect(await audit(page)).toEqual([]);
    });

    for (const area of areas)
      for (const screen of (area.irisScreens ?? []).filter((s) => checkedBy(s, 'a11y')))
        test(`${screenName(screen)}, live ${area.tag}`, async ({ page }) => {
          await stubInstance(page);
          await page.goto(`./#${screen.path}`);
          await expect(page.getByRole('heading', { name: screen.heading, exact: true })).toBeVisible();
          expect(await audit(page)).toEqual([]);
        });
  });
}
