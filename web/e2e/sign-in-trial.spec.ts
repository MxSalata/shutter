import { expect, test, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { signIn as signInArea } from './areas';

/**
 * The live sign-in page of a demo install, on the build IRIS serves. Only that build has it (the demo build is always
 * the trial, which opens signed in), so this file is named to end in `trial.spec.ts`: the `iris-trial` project picks it
 * up by that pattern, and the demo build's project leaves it out. `trial.spec.ts` audits the same page for a
 * hospital's own install (a stub whose health report says it is no demo), where the proof panel is not shown; this
 * stub says it is a demo, so the proof panel, the demo users and the trial card are all on the page.
 */

const LAPTOP = { width: 1280, height: 800 };
const PHONE = { width: 390, height: 844 };

/** The stand-in for a demo install: nobody signed in, and a health report that says it is a demo. */
async function stubDemoInstance(page: Page) {
  await page.route('**/api/shutter/**', (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/me'))
      return route.fulfill({ status: 401, json: { error: 'unauthorized', detail: 'Not signed in' } });
    if (path.endsWith('/health'))
      return route.fulfill({ json: { ok: true, demo: true, version: 'stub', checks: [] } });
    return route.fulfill({ status: 404, json: { error: 'not_found', detail: 'Not on the stub' } });
  });
}

/** The sign-in page, once the health report has said it is a demo (the demo users' disclosure is the sign). */
async function openLive(page: Page) {
  await stubDemoInstance(page);
  await page.goto('./#/login');
  await expect(page.getByRole('button', { name: /^Sign in$/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Demo users' })).toBeVisible();
  await page.waitForLoadState('networkidle');
}

test.describe('the live sign-in page of a demo install, on a laptop', () => {
  test.use({ viewport: LAPTOP });

  test(`shows the proof beside the form, and the way into the trial ${signInArea.tag}`, async ({ page }) => {
    await openLive(page);
    await expect(page.getByRole('heading', { level: 1, name: 'Sign in' })).toBeVisible();
    await expect(
      page.getByRole('heading', {
        level: 2,
        name: 'Shutter fixes a failed HL7 transfer only when it can show the fix is safe.',
      }),
    ).toBeVisible();
    // The board's own figure, and the comparison on its own base as two bars
    await expect(page.getByText('24 of 24', { exact: true })).toBeVisible();
    await expect(page.getByRole('img', { name: 'The board: 11 of 11' })).toBeVisible();
    await expect(page.getByRole('img', { name: 'Rules only: 4 of 11' })).toBeVisible();
    await expect(page.getByText(/recorded with the real agents on IRIS AI Hub/)).toBeVisible();
    // The phone's one line is for the phone
    await expect(page.getByText('Recorded failures: the board 24 of 24')).toBeHidden();
    // The card and its links
    const card = page.getByRole('region', { name: 'New to Shutter?' });
    await expect(card.getByRole('link', { name: 'Take the guided tour of the trial' })).toHaveAttribute(
      'href',
      /\?trial=tour#\/scenarios$/,
    );
    await expect(card.getByRole('link', { name: 'Open the trial' })).toHaveAttribute(
      'href',
      /\?trial#\/home$/,
    );
    // The proof sits on the left and the form on the right, side by side
    const proof = await page.getByRole('region', { name: /^When an HL7 transfer fails/ }).boundingBox();
    const form = await page.getByRole('button', { name: /^Sign in$/ }).boundingBox();
    expect(proof!.x + proof!.width).toBeLessThanOrEqual(form!.x);
  });

  test(`does not scroll sideways at 1024 px ${signInArea.tag}`, async ({ page }) => {
    await page.setViewportSize({ width: 1024, height: 800 });
    await openLive(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(1024);
  });
});

test.describe('the live sign-in page of a demo install, on a phone', () => {
  test.use({ viewport: PHONE });

  test(`gives the proof in one line, with the form above the fold ${signInArea.tag}`, async ({ page }) => {
    await openLive(page);
    await expect(
      page.getByText(
        'Recorded failures: the board 24 of 24. On the same 11 failures: the board 11, Rules only 4.',
      ),
    ).toBeVisible();
    await expect(page.getByText('24 of 24', { exact: true })).toBeHidden();
    const button = await page.getByRole('button', { name: /^Sign in$/ }).boundingBox();
    expect(button!.y + button!.height).toBeLessThanOrEqual(PHONE.height);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(PHONE.width);
  });

  test(`does not scroll sideways at 360 px ${signInArea.tag}`, async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 800 });
    await openLive(page);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360);
  });
});

/** The page in every appearance, on a laptop (the proof in tiles, on a card) and on a phone (the proof as a line, on the page tone). */
for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`accessibility of the live sign-in page of a demo install (axe-core, WCAG 2.1 A/AA), ${mode}`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test(`on a laptop ${signInArea.tag}`, async ({ page }) => {
      await page.setViewportSize(LAPTOP);
      await openLive(page);
      await expect(page.getByText('24 of 24', { exact: true })).toBeVisible();
      expect(await audit(page)).toEqual([]);
    });

    test(`on a phone ${signInArea.tag}`, async ({ page }) => {
      await page.setViewportSize(PHONE);
      await openLive(page);
      expect(await audit(page)).toEqual([]);
    });
  });
}
