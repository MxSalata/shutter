import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import recorded from '@/mocks/onboarding.json';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import NamespacesPage from './NamespacesPage';

const BASE = '/api/shutter/settings/namespaces';
const PATHOLOGY = recorded.namespaces.PATHOLOGY;

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/settings/namespaces', element: <NamespacesPage /> }], {
    initialEntries: ['/settings/namespaces'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Counts the calls that would change something, on top of the recorded answers. */
function countChanges() {
  const calls: { path: string; body: unknown }[] = [];
  server.events.on('request:start', ({ request }) => {
    const url = new URL(request.url).pathname;
    if (/\/(apply|remove|test)$/.test(url))
      void request
        .clone()
        .json()
        .then((body: unknown) => calls.push({ path: url, body }));
  });
  return calls;
}

async function readPlan(user: ReturnType<typeof userEvent.setup>, ns = 'PATHOLOGY') {
  await user.selectOptions(await screen.findByLabelText('Namespace'), ns);
  await user.click(screen.getByRole('button', { name: 'Read the plan' }));
  return screen.findByRole('region', { name: `The plan for ${ns}` });
}

describe('NamespacesPage', () => {
  afterEach(() => server.events.removeAllListeners());

  it('offers the namespaces and changes nothing until a plan is read', async () => {
    const calls = countChanges();
    renderPage();
    const select = await screen.findByLabelText('Namespace');
    expect(within(select).getByRole('option', { name: 'PATHOLOGY' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Apply/ })).not.toBeInTheDocument();
    expect(calls).toEqual([]);
  });

  it("shows the plan's own words first: what would change, the warnings and what is left to a person", async () => {
    const user = userEvent.setup();
    const calls = countChanges();
    renderPage();
    const plan = await readPlan(user);
    for (const a of PATHOLOGY.plan.plan.actions) expect(within(plan).getByText(a.says)).toBeInTheDocument();
    for (const w of PATHOLOGY.plan.plan.warnings) expect(within(plan).getByText(w)).toBeInTheDocument();
    for (const t of PATHOLOGY.plan.plan.todo) expect(within(plan).getByText(t)).toBeInTheDocument();
    for (const o of PATHOLOGY.plan.plan.operations) {
      expect(within(plan).getByRole('rowheader', { name: o.name })).toBeInTheDocument();
    }
    expect(calls).toEqual([]);
  });

  it('applies only after the confirm, with the digest of the plan that was read', async () => {
    const user = userEvent.setup();
    const calls = countChanges();
    renderPage();
    const plan = await readPlan(user);
    await user.click(within(plan).getByRole('button', { name: 'Apply this plan…' }));
    const dialog = await screen.findByRole('dialog', { name: /Apply this plan to PATHOLOGY/ });
    await user.click(within(dialog).getByRole('button', { name: 'Cancel' }));
    expect(calls).toEqual([]);

    await user.click(within(plan).getByRole('button', { name: 'Apply this plan…' }));
    const again = await screen.findByRole('dialog', { name: /Apply this plan to PATHOLOGY/ });
    await user.click(within(again).getByRole('button', { name: 'Apply the plan' }));
    const done = await screen.findByRole('region', { name: 'What changed in PATHOLOGY' });
    expect(within(done).getByText(PATHOLOGY.apply.changed[0])).toBeInTheDocument();
    await waitFor(() => expect(calls).toHaveLength(1));
    expect(calls[0].body).toEqual({ options: {}, digest: PATHOLOGY.plan.digest });
  });

  it('takes the plan away when an option changes, so an old plan cannot be applied', async () => {
    const user = userEvent.setup();
    renderPage();
    await readPlan(user);
    await user.click(screen.getByRole('button', { name: 'Options' }));
    await user.type(await screen.findByLabelText('Receivers'), 'LIMS Out');
    expect(screen.queryByRole('region', { name: 'The plan for PATHOLOGY' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Apply this plan…' })).not.toBeInTheDocument();
  });

  it('says so and shows the new plan when the plan has moved since it was read', async () => {
    const user = userEvent.setup();
    const moved = {
      ...PATHOLOGY.plan,
      plan: { ...PATHOLOGY.plan.plan, warnings: ['A warning that came since'] },
      digest: 'f'.repeat(64),
    };
    server.use(
      http.post(`${BASE}/PATHOLOGY/apply`, () =>
        HttpResponse.json(
          { error: 'plan_changed', detail: 'The plan has changed', ...moved },
          { status: 409 },
        ),
      ),
    );
    renderPage();
    const plan = await readPlan(user);
    await user.click(within(plan).getByRole('button', { name: 'Apply this plan…' }));
    const dialog = await screen.findByRole('dialog', { name: /Apply this plan/ });
    await user.click(within(dialog).getByRole('button', { name: 'Apply the plan' }));
    expect(await screen.findByText(/changed since you read it, so nothing was changed/)).toBeInTheDocument();
    expect(screen.getByText('A warning that came since')).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'What changed in PATHOLOGY' })).not.toBeInTheDocument();
  });

  it('shows the plan but no apply to a user without %Admin_Manage, and says why', async () => {
    const user = userEvent.setup();
    server.use(
      http.get(BASE, () =>
        HttpResponse.json({
          shutterNamespace: 'SHUTTER',
          canApply: false,
          watched: [],
          available: [{ namespace: 'PATHOLOGY' }],
        }),
      ),
    );
    renderPage();
    const plan = await readPlan(user);
    expect(within(plan).queryByRole('button', { name: 'Apply this plan…' })).not.toBeInTheDocument();
    expect(within(plan).getByText(/needs a user holding %Admin_Manage/)).toBeInTheDocument();
  });

  it('has no apply for a plan with nothing to do, or a namespace it cannot read', async () => {
    const user = userEvent.setup();
    server.use(
      http.post(`${BASE}/PATHOLOGY/plan`, () => HttpResponse.json(PATHOLOGY.planAfter)),
      http.post(`${BASE}/DOCUMENTS/plan`, () =>
        HttpResponse.json({
          ...PATHOLOGY.plan,
          plan: {
            ...PATHOLOGY.plan.plan,
            namespace: 'DOCUMENTS',
            actions: [],
            error: 'No production in DOCUMENTS',
          },
        }),
      ),
    );
    renderPage();
    const nothing = await readPlan(user);
    expect(within(nothing).getByText(/Nothing to change/)).toBeInTheDocument();
    expect(within(nothing).queryByRole('button', { name: 'Apply this plan…' })).not.toBeInTheDocument();
    const failed = await readPlan(user, 'DOCUMENTS');
    expect(within(failed).getByText('No production in DOCUMENTS')).toBeInTheDocument();
    expect(within(failed).queryByRole('button', { name: 'Apply this plan…' })).not.toBeInTheDocument();
  });

  it("says in plain words when the user may not read the namespace, keeping the engine's words", async () => {
    const user = userEvent.setup();
    const error =
      'Could not read PATHOLOGY: <PROTECT> 206 Read+11^Shutter.Util.Onboard.1 /usr/irissys/mgr/pathology/';
    server.use(
      http.post(`${BASE}/PATHOLOGY/plan`, () =>
        HttpResponse.json({
          ...PATHOLOGY.plan,
          plan: { ...PATHOLOGY.plan.plan, actions: [], error },
        }),
      ),
    );
    renderPage();
    const plan = await readPlan(user);
    expect(within(plan).getByText(/This user may not read PATHOLOGY/)).toBeInTheDocument();
    expect(within(plan).getByRole('alert')).toHaveTextContent('<PROTECT>');
    expect(within(plan).queryByRole('button', { name: 'Apply this plan…' })).not.toBeInTheDocument();
  });

  it('after an apply, gives the credential as a terminal command with no password field', async () => {
    const user = userEvent.setup();
    renderPage();
    const plan = await readPlan(user);
    await user.click(within(plan).getByRole('button', { name: 'Apply this plan…' }));
    const dialog = await screen.findByRole('dialog', { name: /Apply this plan/ });
    await user.click(within(dialog).getByRole('button', { name: 'Apply the plan' }));
    const next = await screen.findByRole('region', { name: 'Next steps for PATHOLOGY' });
    expect(
      within(next).getByText('Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY")'),
    ).toBeInTheDocument();
    expect(within(next).getByText(/never passes through this app/)).toBeInTheDocument();
    expect(document.querySelector('input[type="password"]')).toBeNull();
    expect(within(next).getByRole('link', { name: 'Site profile' })).toHaveAttribute('href', '/site-profile');
  });

  it("sends a test failure, and shows the case, or the helper's advice when it fails", async () => {
    const user = userEvent.setup();
    server.use(
      http.get(BASE, () =>
        HttpResponse.json({
          shutterNamespace: 'SHUTTER',
          canApply: true,
          watched: [PATHOLOGY.watched],
          available: [],
        }),
      ),
      http.post(`${BASE}/PATHOLOGY/test`, () => HttpResponse.json(PATHOLOGY.test)),
    );
    renderPage();
    const row = await screen.findByRole('row', { name: /PATHOLOGY/ });
    await user.click(within(row).getByRole('button', { name: 'Send a test failure' }));
    const ok = await screen.findByText(/A test case opened/);
    expect(within(ok).getByRole('link', { name: PATHOLOGY.test.case })).toHaveAttribute(
      'href',
      `/cases/${PATHOLOGY.test.case}`,
    );
    server.use(
      http.post(`${BASE}/PATHOLOGY/test`, () =>
        HttpResponse.json({
          ok: false,
          case: '',
          http_status: 401,
          advice: 'HTTP 401: it did not sign in',
          error: '',
        }),
      ),
    );
    await user.click(within(row).getByRole('button', { name: 'Send a test failure' }));
    expect(await screen.findByText('HTTP 401: it did not sign in')).toBeInTheDocument();
  });

  it('shows what a removal would touch first, then what came off and what stays', async () => {
    const user = userEvent.setup();
    const calls = countChanges();
    server.use(
      http.get(BASE, () =>
        HttpResponse.json({
          shutterNamespace: 'SHUTTER',
          canApply: true,
          watched: [PATHOLOGY.watched],
          available: [],
        }),
      ),
    );
    renderPage();
    const row = await screen.findByRole('row', { name: /PATHOLOGY/ });
    await user.click(within(row).getByRole('button', { name: 'Take off…' }));
    const dialog = await screen.findByRole('dialog', { name: /Take PATHOLOGY off/ });
    expect(await within(dialog).findByText(/Shutter Forwarder/)).toBeInTheDocument();
    expect(calls).toEqual([]);
    await user.click(within(dialog).getByRole('button', { name: 'Take it off' }));
    const result = await screen.findByRole('region', { name: 'Taken off PATHOLOGY' });
    expect(within(result).getByText(PATHOLOGY.remove.removed[0])).toBeInTheDocument();
    expect(within(result).getByText(PATHOLOGY.remove.kept[0])).toBeInTheDocument();
  });

  it('says who may use the page to a user who cannot change the site, and asks the server nothing', async () => {
    resetMock('demo');
    let asked = 0;
    server.use(
      http.get(BASE, () => {
        asked += 1;
        return HttpResponse.json({});
      }),
    );
    renderPage();
    expect(await screen.findByText(/An approver who may change the site/)).toBeInTheDocument();
    expect(asked).toBe(0);
  });
});
