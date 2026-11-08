import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { AccessReport, AccessRow } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import { AccessSection } from './AccessSection';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('judge');
  useAppearance.setState({ detail: 'plain' });
});

const ROLES = ['Shutter_Demo', 'Shutter_Judge', 'Shutter_Operator', 'Shutter_Approver', 'Shutter_Trace'];

const row = (
  id: AccessRow['id'],
  needs: string[][],
  cells: [boolean, boolean, boolean, boolean, boolean],
  you: boolean,
  available = true,
): AccessRow => ({
  id,
  needs,
  available,
  roles: Object.fromEntries(ROLES.map((r, i) => [r, cells[i]])),
  you,
});

/** A demo install's report as a judge reads it (the recorded roles, the judge's own column). */
function judgeReport(): AccessReport {
  return {
    demo: true,
    portalHardened: false,
    read: 'recorded',
    recordedAt: '2026-11-08T19:30:00Z',
    roles: ROLES.map((role) => ({ role, installed: true })),
    rows: [
      row('view', [['Shutter_Operate:U']], [true, true, true, true, false], true),
      row('approve', [['Shutter_Approve:U']], [true, true, false, true, false], true),
      row('scenarios', [['Shutter_Scenarios:U']], [false, false, true, true, false], false),
      row('liveAgents', [['Shutter_LiveAgents:U']], [false, true, true, true, false], true),
      row('configure', [['Shutter_Configure:U']], [false, false, false, true, false], false),
      row('inbox', [['%Ens_Portal:U', 'Shutter_Approve:U']], [true, true, false, true, false], true),
      row('guide', [['Shutter_Portal:U'], ['Shutter_Operate:U']], [true, true, true, true, false], true),
      row('trace', [['%Ens_Portal:U', '%Ens_MessageTrace:U']], [true, true, false, true, true], true),
      row('publisher', [['Shutter_Publish:U']], [false, false, true, true, false], false),
    ],
  };
}

function renderAccess(report: AccessReport | null) {
  if (report) server.use(http.get('/api/shutter/access', () => HttpResponse.json(report)));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <AccessSection />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const cellsOf = (r: HTMLElement) => within(r).getAllByRole('cell').map((c) => c.textContent);

describe('AccessSection', () => {
  it('shows what each sign-in may do beside what the user may, with the four roles and a You column', async () => {
    renderAccess(judgeReport());
    const table = await screen.findByRole('table', { name: 'Your access' });
    expect(within(table).getAllByRole('columnheader').map((h) => h.textContent)).toEqual([
      'What',
      'Demo viewer',
      'Judge',
      'Operator',
      'Approver',
      'You',
    ]);
    const rows = within(table).getAllByRole('row').slice(1);
    expect(rows.map((r) => within(r).getByRole('rowheader').textContent)).toEqual([
      'View cases, incidents, evidence and plans',
      'Approve or reject a plan',
      'Run and reset the scenarios',
      'Convene the board and ask the agents new questions, which spends the model budget',
      "Change the site's settings: the site profile, the agent library, the schemas, the review annotations",
      'The Workflow inbox in the Management Portal',
      'The Shutter in IRIS page',
      'The Visual Trace in the Management Portal',
      'The MCP publisher: cases, incidents, evidence and plans for an MCP client',
    ]);
    expect(cellsOf(rows[2])).toEqual(['No', 'No', 'Yes', 'Yes', 'No']);
    expect(cellsOf(rows[3])).toEqual(['No', 'Yes', 'Yes', 'Yes', 'Yes']);
    expect(cellsOf(rows[8])).toEqual(['No', 'No', 'Yes', 'Yes', 'No']);
  });

  it("says which installed role the user's column is, and what the judges' account adds while the demo is on", async () => {
    renderAccess(judgeReport());
    expect(await screen.findByTestId('access-you')).toHaveTextContent(
      'Your column is read from the resources your sign-in holds. It matches Judge (Shutter_Judge).',
    );
    expect(screen.getByTestId('access-judges')).toHaveTextContent(
      "What the judges' account adds to the demo viewer: the agents run for real, on new questions and a convened board, under the day's model budget.",
    );
  });

  it('says so for a sign-in with a role of its own, and leaves the judges out when the demo is off', async () => {
    const r = judgeReport();
    r.demo = false;
    r.rows = r.rows.map((x) => ({ ...x, you: x.id === 'view' || x.id === 'publisher' }));
    renderAccess(r);
    expect(await screen.findByTestId('access-you')).toHaveTextContent(
      /matches none of the roles Shutter installs, so your sign-in has a role of its own\./,
    );
    expect(screen.queryByTestId('access-judges')).not.toBeInTheDocument();
  });

  it('marks a row this instance has nothing to hold for, for everyone', async () => {
    const r = judgeReport();
    r.rows = r.rows.map((x) =>
      x.id === 'guide' ? { ...x, available: false, you: false, roles: Object.fromEntries(ROLES.map((n) => [n, false])) } : x,
    );
    renderAccess(r);
    const table = await screen.findByRole('table', { name: 'Your access' });
    const guide = within(table).getByRole('rowheader', { name: 'The Shutter in IRIS page' }).closest('tr')!;
    expect(cellsOf(guide)).toEqual(['Not on this instance']);
    // The row is left out of the matching, so the judge's column still matches
    expect(screen.getByTestId('access-you')).toHaveTextContent('It matches Judge (Shutter_Judge).');
  });

  it("says when the roles' columns are not recorded yet, and still reads the user's own", async () => {
    const r = judgeReport();
    r.read = 'none';
    delete r.recordedAt;
    r.roles = r.roles.map((x) => ({ ...x, installed: false }));
    r.rows = r.rows.map((x) => ({ ...x, roles: Object.fromEntries(ROLES.map((n) => [n, false])) }));
    renderAccess(r);
    const table = await screen.findByRole('table', { name: 'Your access' });
    const view = within(table).getAllByRole('row')[1];
    expect(cellsOf(view)).toEqual(['Not recorded', 'Not recorded', 'Not recorded', 'Not recorded', 'Yes']);
    expect(screen.getByTestId('access-you')).toHaveTextContent(
      "The roles' columns are not recorded on this instance yet: the production's next start records them.",
    );
  });

  it('names roles, never a person, and keeps "live" out of the first layer', async () => {
    renderAccess(judgeReport());
    await screen.findByRole('table', { name: 'Your access' });
    const words = layer1Words(document.body).join(' ');
    expect(words).not.toMatch(/\blive\b/i);
    expect(words).not.toMatch(/username|password/i);
  });

  it('names the roles behind the columns, the trace role and the needs in the second layer', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderAccess(judgeReport());
    const detail = await screen.findByRole('button', {
      name: 'The roles behind the columns, and the resources each row needs',
    });
    expect(detail).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByText('Shutter_Trace')).toBeInTheDocument();
    expect(screen.getByText(/Shutter_Portal:U, or Shutter_Operate:U/)).toBeInTheDocument();
    expect(screen.getByText(/as recorded at 2026-11-08 19:30:00 UTC/)).toBeInTheDocument();
  });

  it('reads the trial mock as the signed-in judge: the judge column is the user\'s', async () => {
    renderAccess(null);
    expect(await screen.findByTestId('access-you')).toHaveTextContent('It matches Judge (Shutter_Judge).');
    expect(screen.getByTestId('access-judges')).toBeInTheDocument();
  });

  it('says when the access could not be read', async () => {
    server.use(http.get('/api/shutter/access', () => HttpResponse.json({ error: 'boom', detail: 'no' }, { status: 500 })));
    renderAccess(null);
    expect(await screen.findByText('Your access could not be read')).toBeInTheDocument();
  });
});
