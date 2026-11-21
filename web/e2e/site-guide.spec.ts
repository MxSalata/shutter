import { mkdirSync, writeFileSync } from 'node:fs';
import { expect, test, type Page } from './test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go } from './helpers';

/**
 * This site's guide in the trial: opened from the Site profile page, every part and the stamp, printed to an A4 PDF that
 * has a page per part at least, the stamp on every page and none of the app's navigation; then at a phone's width in
 * light and dark, and by keyboard. SITE_GUIDE_OUT names a folder for the PDF and two screenshots for a person to look at.
 */

const PARTS = [
  'Your receivers',
  'Site-wide settings',
  'The gate',
  'Every scenario and what Shutter does with it here',
  'Limits',
];
const OUT = process.env.SITE_GUIDE_OUT;

test.beforeEach(({ page }) => skipWelcome(page));

async function openGuide(page: Page) {
  await go(page, '/site-profile');
  await page.getByRole('link', { name: "Export this site's guide (PDF)" }).click();
  await expect(page.getByRole('heading', { level: 1, name: "This site's guide" })).toBeVisible();
}

/** The number of pages a PDF holds: its page objects. */
function pdfPages(pdf: Buffer): number {
  return (pdf.toString('latin1').match(/\/Type\s*\/Page(?!s)/g) ?? []).length;
}

test('opens from the Site profile page with every part, the stamp and its sample data label', async ({
  page,
}) => {
  // The guide stores nothing: from its opening on, every request to the API is a read
  const writes: string[] = [];
  page.on('request', (r) => {
    if (new URL(r.url()).pathname.includes('/api/shutter/') && r.method() !== 'GET')
      writes.push(`${r.method()} ${r.url()}`);
  });
  await go(page, '/site-profile');
  writes.length = 0;
  await page.getByRole('link', { name: "Export this site's guide (PDF)" }).click();
  await expect(page.getByRole('heading', { level: 1, name: "This site's guide" })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Print or save as PDF' })).toBeEnabled();
  await expect(page).toHaveURL(/#\/site-guide$/);
  for (const part of PARTS) await expect(page.getByRole('heading', { level: 2, name: part })).toBeVisible();
  const stamp = page.getByTestId('site-guide-stamp');
  await expect(stamp).toContainText('Version 7, saved');
  await expect(stamp).toContainText('E1@5,');
  await expect(stamp).toContainText('This guide describes these versions only.');
  await expect(
    page.locator('#site-guide-cover').getByText('Trial (sample data)', { exact: true }),
  ).toBeVisible();
  await expect(page.getByTestId('site-guide-receiver-Downstream Out')).toBeVisible();
  await expect(page.getByTestId('site-guide-entry-E19')).toBeVisible();
  await expect(page.getByRole('table', { name: "The gate's twelve checks" }).getByRole('row')).toHaveCount(
    13,
  );
  // No navigation chrome: the guide is a document of its own
  await expect(page.getByRole('navigation')).toHaveCount(0);
  await expect(page.getByRole('banner')).toHaveCount(0);
  expect(writes).toEqual([]);
  expect(await audit(page)).toEqual([]);
});

test('prints to an A4 PDF with a page per part, the stamp on every page and no navigation', async ({
  page,
}) => {
  await openGuide(page);
  await page.emulateMedia({ media: 'print' });
  // In print the toolbar is gone and every part's foot (the stamp) shows
  await expect(page.locator('.site-guide-toolbar')).toBeHidden();
  const feet = page.getByTestId('site-guide-foot');
  await expect(feet).toHaveCount(6);
  for (const f of await feet.all()) await expect(f).toBeVisible();
  const pdf = await page.pdf({ format: 'A4', printBackground: false });
  const pages = pdfPages(pdf);
  expect(pages).toBeGreaterThanOrEqual(PARTS.length + 1);
  // The page's own measure of each printed page: every part starts on a new page and repeats the stamp on each page
  const layout = await page.evaluate(() => {
    const sheets = [...document.querySelectorAll<HTMLElement>('.site-guide-sheet')];
    return sheets.map((s) => ({
      breaks: getComputedStyle(s).breakBefore,
      foot: getComputedStyle(s.querySelector('tfoot')!).display,
    }));
  });
  expect(layout[0].foot).toBe('table-footer-group');
  expect(layout.slice(1).every((l) => l.breaks === 'page' && l.foot === 'table-footer-group')).toBe(true);
  if (OUT) {
    mkdirSync(OUT, { recursive: true });
    writeFileSync(`${OUT}/site-guide-trial.pdf`, pdf);
  }
  await page.emulateMedia({ media: 'screen' });
});

for (const colorScheme of ['light', 'dark'] as const)
  test.describe(`at 360 px, ${colorScheme}`, () => {
    test.use({ viewport: { width: 360, height: 780 }, colorScheme });

    test('reads with no sideways scroll', async ({ page }) => {
      await openGuide(page);
      const wide = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(wide).toBeLessThanOrEqual(0);
      expect(await audit(page)).toEqual([]);
      if (OUT) await page.screenshot({ path: `${OUT}/site-guide-360-${colorScheme}.png`, fullPage: false });
    });
  });

test('is reached and used by keyboard: the contents jump to a part, and Print is a button', async ({
  page,
}) => {
  await go(page, '/site-guide');
  await expect(page.getByRole('heading', { level: 1, name: "This site's guide" })).toBeVisible();
  await page.evaluate(() => {
    (window as unknown as { printed: number }).printed = 0;
    window.print = () => {
      (window as unknown as { printed: number }).printed += 1;
    };
  });
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Site profile' })).toBeFocused();
  const print = page.getByRole('button', { name: 'Print or save as PDF' });
  for (let i = 0; i < 6 && !(await print.evaluate((b) => b === document.activeElement)); i++)
    await page.keyboard.press('Tab');
  await expect(print).toBeFocused();
  await page.keyboard.press('Enter');
  expect(await page.evaluate(() => (window as unknown as { printed: number }).printed)).toBe(1);
  await page.getByRole('link', { name: 'The gate' }).focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 2, name: 'The gate' })).toBeFocused();
});
