import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { skipWelcome } from './guide';
import { go, signIn } from './helpers';

/**
 * The API reference: the engineer's page, in the navigation only while the Detail switch is on Technical; every route
 * of docs/api/openapi.json listed, filtered, and opened to its tables and curl line; a route named in the address open
 * on arrival, and a shape reached from a route's table.
 */

// The guide's welcome would cover the screens these tests are about; guide.spec.ts tests it
test.beforeEach(({ page }) => skipWelcome(page));

const METHODS = ['get', 'post', 'put', 'patch', 'delete'];
// Read, not imported: a typed import of the whole document costs tsc minutes
const api = JSON.parse(readFileSync(new URL('../../docs/api/openapi.json', import.meta.url), 'utf8')) as {
  paths: Record<string, Record<string, { 'x-writes'?: boolean }>>;
};
/** Every operation of the document: its method, path and whether it writes. */
const operations = Object.entries(api.paths).flatMap(([path, item]) =>
  Object.entries(item)
    .filter(([method]) => METHODS.includes(method))
    .map(([method, op]) => ({ method: method.toUpperCase(), path, writes: op['x-writes'] === true })),
);
const ROUTE_LINE = /^(GET|POST|PUT|PATCH|DELETE) \/api\/shutter/;

test.describe('the API reference @api', () => {
  test('joins the navigation and Home under Technical only, after Configure', async ({ page }) => {
    await signIn(page);
    const nav = page.getByRole('navigation', { name: 'Main' });
    await expect(nav.getByRole('link', { name: 'Cases', exact: false })).toBeVisible();
    await expect(nav.getByRole('link', { name: 'API reference' })).toHaveCount(0);
    await page.getByRole('radiogroup', { name: 'Detail' }).getByText('Technical').click();
    await expect(nav.getByRole('group')).toHaveText([/^Operate/, /^Results/, /^Configure/, /^Technical/]);
    const link = nav.getByRole('link', { name: 'API reference' });
    await expect(link).toBeVisible();
    await link.click();
    await expect(page.getByRole('heading', { name: 'API reference', exact: true, level: 1 })).toBeVisible();
    await expect(page).toHaveURL(/#\/api$/);
    await expect(link).toHaveAttribute('aria-current', 'page');
    // Home lists the same group, so a section is never in one list and missing from the other
    await page.getByRole('link', { name: 'Shutter: home' }).click();
    const technical = page.getByRole('region', { name: 'Technical' });
    await expect(technical.getByRole('link', { name: /^API reference/ })).toBeVisible();
    // Back to Plain: the group goes from both
    await page.getByRole('radiogroup', { name: 'Detail' }).getByText('Plain').click();
    await expect(technical).toHaveCount(0);
    await expect(nav.getByRole('link', { name: 'API reference' })).toHaveCount(0);
  });

  test('lists every route of the document, narrows the list, and opens a route to its tables and curl line', async ({
    page,
  }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/api', { detail: 'technical' });
    await expect(page.getByRole('heading', { name: 'API reference', exact: true, level: 1 })).toBeVisible();
    const routes = page.getByRole('region', { name: 'Routes' });
    const lines = routes.getByRole('button', { name: ROUTE_LINE });
    await expect(lines).toHaveCount(operations.length);
    await expect(routes.getByText(`${operations.length} routes`, { exact: true })).toBeVisible();
    // Changes only: the routes the document marks as writes, each with a filled method badge
    await routes.getByLabel('Show').selectOption('changes');
    await expect(lines).toHaveCount(operations.filter((o) => o.writes).length);
    await routes.getByLabel('Show').selectOption('all');
    // The line's text runs the method badge into the path, so the patterns allow no space between them.
    const find = routes.getByRole('textbox', { name: 'Find' });
    await find.fill('access');
    await expect(lines).toHaveText([/^GET\s*\/api\/shutter\/access(?!\/)/]);
    await expect(lines).toContainText("What each of Shutter's roles may do");
    await find.fill('approvals');
    await expect(lines).toHaveText([
      /^GET\s*\/api\/shutter\/cases\/\{caseId\}\/approvals/,
      /^POST\s*\/api\/shutter\/cases\/\{caseId\}\/approvals/,
      /^GET\s*\/api\/shutter\/incidents\/\{id\}\/approvals/,
      /^POST\s*\/api\/shutter\/incidents\/\{id\}\/approvals/,
      /^POST\s*\/api\/shutter\/incidents\/\{id\}\/chains\/\{seq\}\/approvals/,
      /^POST\s*\/api\/shutter\/outages\/\{id\}\/approvals/,
    ]);
    const approve = lines.filter({ hasText: /^POST\s*\/api\/shutter\/cases\/\{caseId\}\/approvals/ });
    await approve.click();
    await expect(approve).toHaveAttribute('aria-expanded', 'true');
    const panel = routes.locator(`#${await approve.getAttribute('aria-controls')}`);
    await expect(panel).toContainText('Shutter_Approve');
    await expect(
      panel.getByRole('table', { name: 'Parameters' }).getByRole('rowheader', { name: /caseId/ }),
    ).toBeVisible();
    await expect(
      panel.getByRole('table', { name: 'Replies' }).getByRole('row', { name: /^409/ }),
    ).toContainText('wrong_state');
    await expect(panel.getByLabel('Example body')).toContainText('"decision": "approve"');
    await expect(panel.getByLabel(/as curl$/)).toContainText("-H 'X-Requested-With: Shutter'");
    await expect(panel.getByRole('button', { name: 'Copy the command' })).toBeVisible();
  });

  test('opens the route the address names, and reaches a shape from its table', async ({ page }) => {
    await signIn(page, { detail: 'technical' });
    await go(page, '/api?op=caseApprove', { detail: 'technical' });
    const routes = page.getByRole('region', { name: 'Routes' });
    const approve = routes.getByRole('button', {
      name: /^POST \/api\/shutter\/cases\/\{caseId\}\/approvals/,
    });
    await expect(approve).toHaveAttribute('aria-expanded', 'true');
    const panel = routes.locator(`#${await approve.getAttribute('aria-controls')}`);
    await panel.getByRole('button', { name: 'ApprovalDecided' }).click();
    const shape = page
      .getByRole('region', { name: 'Shapes' })
      .getByRole('button', { name: /^ApprovalDecided/ });
    await expect(shape).toHaveAttribute('aria-expanded', 'true');
    await expect(shape).toBeFocused();
    await expect(shape).toBeInViewport();
    const shapePanel = page.locator(`#${await shape.getAttribute('aria-controls')}`);
    await expect(
      shapePanel.getByRole('table', { name: 'ApprovalDecided' }).getByRole('row', { name: /^approver/ }),
    ).toContainText('The signed-in user, never a name from the body.');
  });
});
