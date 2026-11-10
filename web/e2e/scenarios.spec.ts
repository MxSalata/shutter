import { expect, test } from '@playwright/test';
import { audit, choosePastel, MODES } from './axe';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The Scenarios page: Run and Reset greyed out for the live hospital's public role; the three starters' Run buttons in one
 * line; the guided path's links; each row's latest case by outcome; and on a phone each description toggle named after
 * its scenario, and the rows as compact cards that never scroll sideways.
 */

/** The live hospital's public role: the address keeps `?as=demo` in every step. */
const AS_DEMO = { as: 'demo' } as const;

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

test.describe('the live hospital, as the public role sees it @scenarios', () => {
  test("greys out Run and Reset, and says once that the online demo's hospital plays its stories by itself", async ({
    page,
  }) => {
    await signIn(page, AS_DEMO);
    await expect(page.getByText(/hospital plays its stories by itself/)).toHaveCount(1);
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list).toBeVisible();
    const runs = list.getByRole('button', { name: /^Run / });
    await expect(runs.first()).toBeVisible();
    expect(await runs.count()).toBeGreaterThan(20);
    for (const run of await runs.all()) await expect(run).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Reset' })).toBeDisabled();
    await expect(page.getByRole('columnheader', { name: 'Play' })).toBeVisible();
    // The three first cases still open their cases
    const first = page.getByRole('region', { name: 'Three to look at first' });
    await expect(first.getByRole('link', { name: /^Open C-/ })).toHaveCount(3);
    for (const run of await first.getByRole('button', { name: /^Run / }).all())
      await expect(run).toBeDisabled();
  });
});

for (const { colorScheme, contrast, palette } of MODES)
  test.describe(`the public role's greyed-out controls, ${palette} ${colorScheme}, contrast ${contrast} @scenarios`, () => {
    test.use({ colorScheme, contrast });
    if (palette === 'pastel') test.beforeEach(({ page }) => choosePastel(page));

    test('pass the accessibility check, with the small diagrams', async ({ page }) => {
      await signIn(page, AS_DEMO);
      await expect(
        page.getByRole('region', { name: 'Every scenario' }).getByRole('img').first(),
      ).toBeVisible();
      await expect(page.getByRole('status')).toHaveCount(0);
      expect(await audit(page)).toEqual([]);
    });
  });

for (const width of [360, 390, 1280, 1920])
  test.describe(`the small diagrams at ${width} px @scenarios`, () => {
    test.use({ viewport: { width, height: 900 } });

    for (const opened of [{}, AS_DEMO, { detail: 'technical' as const }])
      test(`stay small, keep their words inside their marks, and never scroll the page sideways, as ${JSON.stringify(opened)}`, async ({
        page,
      }) => {
        await signIn(page, opened);
        const list = page.getByRole('region', { name: 'Every scenario' });
        await expect(list.locator('.scenario-diagram')).toHaveCount(26);
        const found = await page.evaluate(() =>
          [...document.querySelectorAll<SVGSVGElement>('.scenario-diagram')].flatMap((svg) => {
            const bad: string[] = [];
            const box = svg.getBoundingClientRect();
            // Two rows: the story, then the expected end on a row of its own (a first card adds 6 px above)
            if (box.height > 90 || box.width > 305) bad.push(`${box.width}x${box.height}`);
            if (box.right > window.innerWidth) bad.push('past the window');
            if (!svg.getAttribute('aria-label')?.includes('. Expected: ')) bad.push('no label');
            // No text drawn below 12 px: the drawing's own sizes, times how much the page has scaled it down
            const scale = box.width / Number(svg.getAttribute('width'));
            for (const t of svg.querySelectorAll('text')) {
              const size = parseFloat(getComputedStyle(t).fontSize) * scale;
              if (size < 11.95) bad.push(`${t.textContent} at ${size.toFixed(1)} px`);
            }
            for (const g of svg.querySelectorAll('g')) {
              const [rect, text] = [g.querySelector(':scope > rect'), g.querySelector(':scope > text')] as [
                SVGGraphicsElement | null,
                SVGGraphicsElement | null,
              ];
              if (!rect || !text) continue;
              const [r, t] = [rect.getBBox(), text.getBBox()];
              const room = g.querySelector('.diagram-cross') ? 12 : 0;
              if (t.x < r.x + 1 || t.x + t.width > r.x + r.width - room - 1)
                bad.push(`${text.textContent} overflows`);
            }
            const limit = Number(svg.getAttribute('width'));
            // Captions in the order drawn, row by row: stacked, the end's caption is on a row of its own
            for (const row of [false, true]) {
              const captions = [...svg.querySelectorAll<SVGGraphicsElement>('.diagram-caption')]
                .filter((c) => !!c.closest('[data-row="end"]') === row)
                .map((c) => ({ box: c.getBBox(), words: c.textContent }));
              captions.forEach(({ box: c, words }, i) => {
                if (c.x < 0 || c.x + c.width > limit) bad.push(`caption ${words} out`);
                if (i && c.x < captions[i - 1].box.x + captions[i - 1].box.width)
                  bad.push(`${words} overlaps`);
              });
            }
            return bad.length ? [`${svg.getAttribute('aria-label')?.slice(0, 12)}: ${bad.join(', ')}`] : [];
          }),
        );
        expect(found).toEqual([]);
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
      });
  });

test.describe('the page at 1280 px @scenarios', () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test.beforeEach(({ page }) => signIn(page));

  test('Back from a case returns to the run mode and the filter', async ({ page }) => {
    await go(page, '/scenarios');
    // One after the other with no wait, on a machine slowed four times: the second choice keeps the first
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
    await page.getByRole('radio', { name: /^Rules only/ }).click();
    await page.getByText(/^Escalate \d+$/).click();
    await expect(page).toHaveURL(/mode=rules&outcome=escalate$/);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: 1 });
    const list = page.getByRole('region', { name: 'Every scenario' });
    // Its header and the eight that should escalate in Rules only
    await expect(list.getByRole('row')).toHaveCount(9);
    await list.getByRole('link', { name: /^C-/ }).first().click();
    await expect(page).toHaveURL(/#\/cases\/C-/);
    await page.goBack();
    await expect(page).toHaveURL(/mode=rules&outcome=escalate$/);
    await expect(page.getByRole('radio', { name: /^Rules only/ })).toBeChecked();
    await expect(list.getByRole('row')).toHaveCount(9);
  });

  test("lines up the three starters' Run buttons", async ({ page }) => {
    await go(page, '/scenarios');
    const first = page.getByRole('region', { name: 'Try these three first' });
    const runs = [
      first.getByRole('button', { name: 'Run S2 in Board mode' }),
      first.getByRole('button', { name: 'Run S8 in Board mode' }),
      first.getByRole('button', { name: 'Run S20 in Rules only mode' }),
    ];
    const tops: number[] = [];
    for (const run of runs) tops.push((await run.boundingBox())!.y);
    expect(Math.max(...tops) - Math.min(...tops)).toBeLessThanOrEqual(1);
  });

  test('names the opening region by its sentence alone while its fold is closed', async ({ page }) => {
    await go(page, '/scenarios');
    await expect(page.getByRole('button', { name: 'What a scenario does' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    await expect(page.getByRole('region', { name: /^Shutter resends a failed HL7 delivery/ })).toBeVisible();
  });

  test('leads through the guided path by its links, each step a sentence with the rest behind More', async ({
    page,
  }) => {
    await go(page, '/scenarios');
    const card = page.getByRole('region', { name: 'Then follow this path' });
    await expect(card.getByRole('listitem')).toHaveCount(6);
    for (const name of [
      'Case C-000002',
      'Case C-000021',
      'Case C-000008',
      'Rules only and Board side by side',
      'Case C-000012',
      'Incident I-000001',
      'Settings and costs',
      'Evaluation',
    ])
      await expect(card.getByRole('link', { name, exact: true })).toBeVisible();
    const more = card.getByRole('button', { name: 'More about step 1' });
    await expect(more).toHaveAttribute('aria-expanded', 'false');
    await more.click();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    await expect(card.getByText(/one conditional write, then "Verified"/)).toBeVisible();
  });

  test("shows each row's latest case by its outcome, with how it compares with what the scenario expects", async ({
    page,
  }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    const s5 = list.locator('tr[data-scenario="S5"]');
    await expect(s5.getByText('Delivered, verified')).toBeVisible();
    await expect(s5.getByText('As expected', { exact: true })).toBeVisible();
    await expect(s5).toHaveAttribute('data-tone', 'positive');
    await expect(list.locator('tr[data-scenario="S1"]')).toContainText(
      'Recorded: board as expected; Rules only stopped by the gate',
    );
  });

  test('adds the HL7 events and the proof bases in Technical', async ({ page }) => {
    await go(page, '/scenarios', { detail: 'technical' });
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list.locator('tr[data-scenario="S2"]').getByText('A01, A02 fails')).toBeVisible();
    await expect(
      page.getByText(/24 scored passes, proposed action; 11 scenarios, played end to end/),
    ).toBeVisible();
  });
});

test.describe('a phone at 390 px @scenarios', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test.beforeEach(({ page }) => signIn(page));

  test("each scenario's description toggle is named after its scenario", async ({ page }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    await expect(list.getByRole('button', { name: /^Run S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: /^More about S\d+[a-z]?$/ }).first()).toBeVisible();
    await expect(list.getByRole('button', { name: 'More', exact: true })).toHaveCount(0);
  });

  test('shows each scenario as a compact card, within the width of the phone', async ({ page }) => {
    await go(page, '/scenarios');
    const list = page.getByRole('region', { name: 'Every scenario' });
    const s2 = list.locator('tr[data-scenario="S2"]');
    await expect(s2.getByRole('button', { name: 'Run S2' })).toBeVisible();
    const box = (await s2.boundingBox())!;
    expect(box.x + box.width).toBeLessThanOrEqual(390);
    // The cells name themselves: no column names are drawn above them
    const label = await s2
      .locator('td[data-label="What should happen"]')
      .evaluate((td) => getComputedStyle(td, '::before').display);
    expect(label).toBe('none');
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
  });
});
