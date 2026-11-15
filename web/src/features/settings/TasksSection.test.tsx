import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { MemoryRouter } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import { TasksSection } from './TasksSection';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  useAppearance.setState({ detail: 'plain' });
});

/** The recorded demo's profile with recovery as a demo seeds it, unless a test says otherwise. */
function answer(over: {
  settings?: Record<string, unknown>;
  recovery?: Record<string, unknown>;
  profile?: Record<string, unknown>;
}) {
  const profile = { ...fixtures.siteProfile.profile, recovery: { mode: 'enabled' }, ...over.profile };
  server.use(
    http.get('/api/shutter/site-profile', () => HttpResponse.json({ ...fixtures.siteProfile, profile })),
  );
  if (over.settings)
    server.use(
      http.get('/api/shutter/settings', () => HttpResponse.json({ ...fixtures.settings, ...over.settings })),
    );
  if (over.recovery)
    server.use(
      http.get('/api/shutter/recovery-control', () =>
        HttpResponse.json({
          mode: 'enabled',
          generation: 1,
          stopped: false,
          stoppedAt: '',
          stoppedBy: '',
          stopReason: '',
          outstanding: [],
          outstandingCount: 0,
          readable: true,
          covers: '',
          doesNotCover: '',
          ...over.recovery,
        }),
      ),
    );
}

function renderTasks() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <TasksSection />
        </MemoryRouter>
      </QueryClientProvider>
    </MantineProvider>,
  );
}

/** Opens the section's one line, as a reader does: the list and what it reads come only then. */
async function open() {
  await userEvent.click(await screen.findByRole('button', { name: 'Each task, and whether it is ready' }));
}

const row = async (id: string) => screen.findByTestId(`task-${id}`);

describe('TasksSection', () => {
  it('keeps one line on the first layer, and reads nothing until it is opened', async () => {
    answer({});
    const asked: string[] = [];
    const listen = ({ request }: { request: Request }) => asked.push(new URL(request.url).pathname);
    server.events.on('request:start', listen);
    try {
      const { container } = renderTasks();
      const line = await screen.findByRole('button', { name: 'Each task, and whether it is ready' });
      expect(line).toHaveAttribute('aria-expanded', 'false');
      expect(container.querySelector('[data-tech-detail]')).toBeEmptyDOMElement();
      expect(asked).toEqual([]);
      await userEvent.click(line);
      expect(await screen.findByTestId('tasks-summary')).toHaveTextContent('All 6 ready for you.');
      expect(asked).toEqual(
        expect.arrayContaining([
          '/api/shutter/me',
          '/api/shutter/settings',
          '/api/shutter/recovery-control',
          '/api/shutter/site-profile',
          '/api/shutter/health',
          '/api/shutter/costs',
        ]),
      );
    } finally {
      server.events.removeListener('request:start', listen);
    }
  });

  it('lists the six tasks, each with its state, and changes nothing', async () => {
    answer({});
    renderTasks();
    await open();
    const list = await screen.findByRole('list', { name: 'Your tasks' });
    const rows = within(list).getAllByRole('listitem');
    expect(rows.map((r) => within(r).getByRole('heading', { level: 3 }).textContent)).toEqual([
      'Read cases and recorded runs',
      'Run a scenario',
      'Ask the agents a question of your own',
      "Approve a recovery or an incident's release",
      'Escalate a case by email',
      'Close a case handled by hand',
    ]);
    for (const r of rows) expect(r).toHaveAttribute('data-state', 'ready');
    expect(within(await row('approve')).getByText('Ready')).toBeInTheDocument();
    // Read only: nothing here to press or type in
    const section = screen.getByRole('region', { name: 'Your tasks' });
    // Its one button opens and closes the list
    expect(
      within(section)
        .getAllByRole('button')
        .map((b) => b.textContent),
    ).toEqual(['Each task, and whether it is ready']);
    expect(within(section).queryAllByRole('textbox')).toHaveLength(0);
  });

  it('says what is set up, what holds now with the time it was read, and what was seen, apart', async () => {
    answer({});
    renderTasks();
    await open();
    const ask = await row('ask');
    expect(ask.querySelector('[data-kind="set up"]')).toHaveTextContent('Set up: A model key is configured.');
    const now = ask.querySelector('[data-kind="now"]')!;
    expect(now).toHaveTextContent(/^Now: The model can be asked\. Read .+\.$/);
    const time = now.querySelector('time')!;
    expect(time.getAttribute('dateTime')).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    // What was seen: the health report's newest run that reached a model, with when it started
    const seen = ask.querySelector('[data-kind="seen"]')!;
    expect(seen).toHaveTextContent(
      /^Seen: The newest run that reached a real model answered\. Started .+\.$/,
    );
    expect(seen.querySelector('time')).toHaveAttribute('dateTime', fixtures.health.last_live_run.at);
  });

  it("shows the rows before the health report answers, with the costs' count, then the newest run once it does", async () => {
    answer({});
    let release = () => {};
    const held = new Promise<void>((r) => (release = r));
    server.use(
      http.get('/api/shutter/health', async () => {
        await held;
        return HttpResponse.json({ recorded: fixtures.source, ...fixtures.health });
      }),
    );
    try {
      renderTasks();
      await open();
      expect(await screen.findByTestId('tasks-summary')).toHaveTextContent('All 6 ready for you.');
      const ask = await row('ask');
      const seen = () => ask.querySelector('[data-kind="seen"]');
      expect(seen()).toHaveTextContent('Seen: No agent run has reached a real model on this instance yet.');
      release();
      await vi.waitFor(() =>
        expect(seen()).toHaveTextContent(
          /^Seen: The newest run that reached a real model answered\. Started .+\.$/,
        ),
      );
    } finally {
      release();
    }
  });

  it('says a run refused before any call in plain words, and its status only on Technical', async () => {
    answer({});
    server.use(
      http.get('/api/shutter/health', () =>
        HttpResponse.json({
          recorded: fixtures.source,
          ...fixtures.health,
          last_live_run: { ...fixtures.health.last_live_run, status: 'budget_exhausted' },
        }),
      ),
    );
    renderTasks();
    await open();
    const ask = await row('ask');
    await vi.waitFor(() =>
      expect(ask.querySelector('[data-kind="seen"]')).toHaveTextContent(
        /^Seen: The newest run meant for a real model was refused before any call to it: the day's live AI budget, or its requester's share of it, was used up\. Started .+\.$/,
      ),
    );
    const seen = ask.querySelector('[data-kind="seen"]')!;
    expect(seen).not.toHaveTextContent('reached');
    expect(seen).not.toHaveTextContent('budget_exhausted');
    act(() => useAppearance.setState({ detail: 'technical' }));
    expect(seen).toHaveTextContent(/Status budget_exhausted\. Started /);
    expect(seen.querySelector('code')).toHaveTextContent('budget_exhausted');
  });

  it('in shadow mode: the approval is not now and says how recovery is enabled; an escalation reads Not sent', async () => {
    answer({ recovery: { mode: 'shadow' }, profile: { recovery: { mode: 'shadow' } } });
    renderTasks();
    await open();
    expect(await screen.findByTestId('tasks-summary')).toHaveTextContent(
      '5 of 6 ready for you. Not now: approving.',
    );
    const approve = await row('approve');
    expect(approve).toHaveAttribute('data-state', 'blocked');
    expect(within(approve).getByText('Not now')).toBeInTheDocument();
    expect(within(approve).getByTestId('task-condition')).toHaveAttribute('data-code', 'shadow');
    expect(within(approve).getByTestId('task-next')).toHaveTextContent(
      /^Next: Enabling recovery is the site's decision\./,
    );
    const escalate = await row('escalate');
    expect(escalate).toHaveAttribute('data-state', 'limited');
    expect(within(escalate).getByText('Ready, with a limit')).toBeInTheDocument();
    // What it does, then the limit and its next step
    expect(within(escalate).getByText(/^Emails the team the site names/)).toBeInTheDocument();
    expect(within(escalate).getByTestId('task-condition')).toHaveTextContent(/reads Not sent/);
  });

  it('with no model key: asking is not now, and the next step says how a key is added', async () => {
    answer({ settings: { providerConfigured: false } });
    renderTasks();
    await open();
    const ask = await row('ask');
    expect(ask).toHaveAttribute('data-state', 'blocked');
    expect(within(ask).getByTestId('task-condition')).toHaveTextContent(
      'No model key is configured here, so the agents only replay recordings.',
    );
    expect(within(ask).getByTestId('task-next')).toHaveTextContent(/ANTHROPIC_API_KEY/);
    expect(await row('scenario')).toHaveAttribute('data-state', 'limited');
  });

  it('with the API mimic on: asking is not now, as the Ask panel says, and no line says a model can be asked', async () => {
    answer({ settings: { mock: true, mockConfig: 'AI.LLM.ShutterMock', mockModel: 'mock' } });
    renderTasks();
    await open();
    const ask = await row('ask');
    expect(ask).toHaveAttribute('data-state', 'blocked');
    expect(within(ask).getByTestId('task-condition')).toHaveAttribute('data-code', 'mimic');
    expect(within(ask).getByTestId('task-next')).toHaveTextContent(
      /^Next: Pick a suggested question on a case/,
    );
    expect(ask.querySelector('[data-kind="set up"]')).toHaveTextContent(
      'Set up: The API mimic is on, a test fixture: no model is called.',
    );
    expect(ask.querySelector('[data-kind="now"]')).toBeNull();
    expect(screen.getByTestId('tasks-summary')).toHaveTextContent('Not now: your own questions');
  });

  it("for the public demo's own user: the role's reason, with the conditions that also apply under Also", async () => {
    resetMock('demo');
    answer({ recovery: { stopped: true, stoppedBy: 'operator', stopReason: 'receiver upgrade' } });
    renderTasks();
    await open();
    const ask = await row('ask');
    expect(within(ask).getByTestId('task-condition')).toHaveAttribute('data-code', 'role');
    const approve = await row('approve');
    expect(within(approve).getByTestId('task-condition')).toHaveTextContent(
      'Recovery is stopped by operator: receiver upgrade. No new recovery call is admitted.',
    );
    expect(within(approve).getByTestId('task-next')).toHaveTextContent(
      /^Next: A person who may both approve and change the site's settings clears it/,
    );
  });

  it('says "not known" when the recovery control cannot be read, never ready', async () => {
    answer({});
    server.use(
      http.get('/api/shutter/recovery-control', () =>
        HttpResponse.json({ error: 'internal', detail: 'boom' }, { status: 500 }),
      ),
    );
    renderTasks();
    await open();
    const approve = await row('approve');
    expect(approve).toHaveAttribute('data-state', 'unknown');
    expect(within(approve).getByText('Not known')).toBeInTheDocument();
  });
});
