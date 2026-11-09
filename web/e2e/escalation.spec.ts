import { expect, test, type Page } from '@playwright/test';
import { audit } from './axe';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';
import { area } from './areas/case';

/**
 * A case's escalation email with no mail server (CONTRACTS 10, v1.53): the trial saves it as an email file, as an instance
 * with no mail server does, so it reads "Saved, not delivered", never Sent, and the case can then be marked handled. The
 * S8 board case C-000008 stands escalated with the team in the recording.
 */

test.beforeEach(({ page }) => skipWelcome(page));

/** Saves a picture for the record when E2E_SHOTS names a folder. */
async function shot(page: Page, name: string, target?: { screenshot: Page['screenshot'] }) {
  if (!process.env.E2E_SHOTS) return;
  await (target ?? page).screenshot({ path: `${process.env.E2E_SHOTS}/${name}.png`, animations: 'disabled' });
}

for (const colorScheme of ['light', 'dark'] as const)
  for (const width of [1280, 390])
    test.describe(`an escalation saved as an email file, ${colorScheme}, ${width} px ${area.tag}`, () => {
      test.use({ colorScheme, viewport: { width, height: 900 } });

      test('reads saved, not delivered, with the queue on the timeline, and passes axe', async ({ page }) => {
        // The whole flow, an axe run and the audit trail: slow beside the other workers of a full run
        test.slow();
        await signIn(page);
        await go(page, '/cases/C-000008');
        const panel = page.getByRole('region', { name: 'Escalations' });
        await panel.getByRole('button', { name: /^Escalate to / }).click();
        const dialog = page.getByRole('dialog', { name: /^Escalate to / });
        await expect(dialog.getByTestId('confirm-consequence')).toHaveText(
          'Sending saves it as an email file in the trial, as on an instance with no mail server. No email leaves this browser.',
        );
        await dialog.getByRole('button', { name: 'Send' }).click();
        await expect(dialog).toHaveCount(0);
        await expect(page.getByText('Saved in the trial, not delivered')).toBeVisible();
        await expect(panel.getByText('Saved, not delivered', { exact: true })).toBeVisible();
        await expect(panel.getByText('Sent', { exact: true })).toHaveCount(0);
        await panel.getByRole('button', { name: /Escalation 1/ }).click();
        await expect(panel.getByTestId('escalation-saved')).toHaveText(
          'Saved as an email file, not delivered: no mail server is set, so nobody was emailed. Pass the file on, or set the mail server and send it again.',
        );
        await expect(panel.getByText(/^Digest of the text saved: /)).toBeVisible();
        await expect(panel.getByRole('button', { name: 'Send it again…' })).toBeVisible();
        await expect(panel.getByRole('button', { name: /Mark as handled by the team/ })).toBeVisible();
        // The toast has gone, so the check reads the page as it stands
        await page.locator('.mantine-Notification-root').evaluateAll((n) => n.forEach((x) => x.remove()));
        const sideways = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(sideways).toBeLessThanOrEqual(0);
        expect(await audit(page)).toEqual([]);
        await shot(page, `escalation-saved-${width}-${colorScheme}`, panel);
        // The timeline says the person queued it and the operation saved it, not that anyone was emailed
        await page.getByRole('tab', { name: 'Audit trail' }).click();
        const timeline = page.getByRole('region', { name: 'Timeline' });
        await expect(
          timeline.getByText(/^Escalation 1 queued by approver for .*; digest of the text queued /),
        ).toBeVisible();
        await expect(
          timeline.getByText(
            /^Escalation 1 saved as an email file, not delivered: .*No mail server is set, so nobody was emailed\.$/,
          ),
        ).toBeVisible();
      });
    });
