import { expect, test, type Page } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * Health: the trial's report reads as a recording (the verdict in the past tense, when it was read, where the agents'
 * runs were recorded), the group links, the reason chip's note, the phone's rows, and the page with every disclosure
 * open in the five appearances. The recorded instance was a demo installation without AI Hub or a purge task.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

/** Opens every disclosure of the page and waits for the panels to finish opening. */
async function openEverything(page: Page) {
  for (const toggle of await page.locator('.tech-detail-toggle').all())
    if ((await toggle.getAttribute('aria-expanded')) !== 'true') await toggle.click();
  await expect(page.locator('.tech-detail-toggle[aria-expanded="false"]')).toHaveCount(0);
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every((a) => a.playState !== 'running' || a.effect?.getTiming().iterations === Infinity),
  );
}

test.describe('the trial report @health', () => {
  test('opens as a recording: ready, with its core checks, when it was read and where the agents ran', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/health');
    await expect(page.getByRole('heading', { name: 'Health', exact: true })).toBeVisible();
    const hero = page.getByRole('region', { name: 'Ready' });
    await expect(hero.getByRole('heading', { level: 2 })).toHaveText(
      'The recorded instance was ready: its message engine was running and every core check passed (7 of 7).',
    );
    await expect(hero.getByRole('list', { name: 'Core checks' }).getByRole('listitem')).toHaveCount(7);
    await expect(hero).toContainText('Shutter.Production');
    await expect(hero).toContainText('read 20 Oct 2026, 17:55 UTC');
    await expect(hero).toContainText('Board runs recorded on IRIS AI Hub (build 154); replayed here');
    await expect(hero).not.toContainText(/not needed/i);
    await expect(
      page.getByText('This is the report of the instance the trial was recorded on.'),
    ).toBeVisible();
  });

  test('groups the rows and marks the pieces the recorded instance did not have', async ({ page }) => {
    await signIn(page);
    await go(page, '/health');
    const agents = page.getByRole('region', { name: 'Agents and AI Hub' });
    await expect(agents).toContainText(
      "The agents' runs were recorded on IRIS AI Hub; this report's instance replays them.",
    );
    await expect(agents).toContainText('2 not on the recorded instance');
    await expect(agents).toContainText('3 specialist agents and the coordinator agent');
    const hub = agents
      .getByRole('row')
      .filter({ has: page.getByRole('rowheader', { name: 'AI Hub installed' }) });
    await expect(hub).toContainText('No');
    // The note is in the chip's tooltip, which the keyboard reaches too
    const chip = hub.getByText('Not on the recorded instance');
    await chip.hover();
    await expect(page.getByRole('tooltip')).toContainText(
      "The board's runs were recorded with the real agents on the AI Hub build and replay here.",
    );
    await page.mouse.move(0, 0);
    await hub.locator('[tabindex="0"]', { hasText: 'Not on the recorded instance' }).focus();
    await expect(page.getByRole('tooltip')).toContainText('which had no AI Hub');
    const install = page.getByRole('region', { name: 'Installation and licence' });
    await expect(install).toContainText(
      'Concurrent User licence: 1 unit consumed, 7 available, up to 25 connections',
    );
  });

  test('has one line of links to the groups, which move focus to the heading', async ({ page }) => {
    await signIn(page);
    await go(page, '/health');
    const links = page.getByRole('navigation', { name: 'Groups' });
    await expect(links).toContainText('Production 4 of 4');
    await expect(links).toContainText('Web applications 3 of 3');
    await links.getByRole('button', { name: 'Installation and licence' }).click();
    await expect(page.getByRole('heading', { level: 2, name: 'Installation and licence' })).toBeFocused();
    await links.getByRole('button', { name: 'Production 4 of 4 pass' }).click();
    await expect(page.getByRole('heading', { level: 2, name: 'Production' })).toBeFocused();
  });

  test('keeps the provenance and the API response behind disclosures, and opens the data ones in Technical', async ({
    page,
  }) => {
    await signIn(page);
    await go(page, '/health');
    const provenance = page.getByRole('button', { name: 'Where this report comes from' });
    const api = page.getByRole('button', { name: 'The report as the API sends it' });
    await expect(provenance).toHaveAttribute('aria-expanded', 'false');
    await expect(api).toHaveAttribute('aria-expanded', 'false');
    await provenance.click();
    await expect(page.getByText("Recorded from Shutter's REST API at 20 Oct 2026, 17:55 UTC")).toBeVisible();
    // Technical opens the data disclosures (the licence fields, the API response) and leaves the explanation closed
    await go(page, '/health', { detail: 'technical' });
    await expect(page.getByRole('button', { name: 'The report as the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(page.getByRole('button', { name: 'Licence fields' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await expect(page.getByRole('button', { name: 'Where this report comes from' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });
});

test.describe('on a phone @health', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('puts a short value beside its label and a long one under it', async ({ page }) => {
    await signIn(page);
    await go(page, '/health');
    const production = page.getByRole('region', { name: 'Production', exact: true });
    const parts = async (name: string) => {
      const row = production
        .getByRole('row')
        .filter({ has: page.getByRole('rowheader', { name, exact: true }) });
      const th = await row.getByRole('rowheader').boundingBox();
      const td = await row.getByRole('cell').boundingBox();
      return { th: th!, td: td! };
    };
    const short = await parts('Production class compiled');
    expect(Math.abs(short.td.y - short.th.y)).toBeLessThan(12);
    expect(short.td.x).toBeGreaterThan(short.th.x);
    const long = await parts('ADT inbound folder');
    expect(long.td.y).toBeGreaterThanOrEqual(long.th.y + long.th.height - 2);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });
});

for (const { colorScheme, contrast, palette } of MODES) {
  const mode = `${palette === 'pastel' ? 'pastel' : colorScheme}${contrast === 'more' ? ', high contrast' : ''}`;
  test.describe(`with every disclosure open, ${mode} @health`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test('passes axe-core', async ({ page }) => {
      await signIn(page);
      await go(page, '/health');
      await expect(page.getByRole('heading', { name: 'Health', exact: true })).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      await openEverything(page);
      expect(await audit(page)).toEqual([]);
    });
  });
}
