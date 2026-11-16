import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { catalogueView, clearSiteEntries, resetMock, SITE_ENTRIES_EXAMPLE } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import SiteGuidePage from './SiteGuidePage';

/** This site's guide on a live page: every part from the install's answers, the stamp, the site's own entries, rights. */

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => resetMock('operator'));

type Profile = { receivers: Record<string, unknown>[] } & Record<string, unknown>;

/** A part of the guide, by its section's id, once the guide has rendered. */
async function part(id: string): Promise<HTMLElement> {
  await screen.findByTestId('site-guide-stamp');
  return document.getElementById(id)!;
}

/** The recorded site profile, changed as a test needs it, at the version the catalogue was made under. */
function withProfile(edit: (profile: Profile) => void) {
  server.use(
    http.get('/api/shutter/site-profile', () => {
      const recorded = structuredClone(fixtures.siteProfile) as unknown as { profile: Profile };
      edit(recorded.profile);
      return HttpResponse.json(recorded);
    }),
  );
}

function renderGuide() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/site-guide', element: <SiteGuidePage /> },
      { path: '/site-profile', element: <p>Site profile</p> },
    ],
    { initialEntries: ['/site-guide'] },
  );
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const PARTS = [
  'Your receivers',
  'Site-wide settings',
  'The gate',
  'Every scenario and what Shutter does with it here',
  'Limits',
];

describe("This site's guide", () => {
  it('has the cover and the five parts in order, with the stamp at the foot of each', async () => {
    renderGuide();
    expect(await screen.findByRole('heading', { level: 1, name: "This site's guide" })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(PARTS);
    const feet = screen.getAllByTestId('site-guide-foot');
    expect(feet).toHaveLength(6);
    const view = catalogueView();
    for (const f of feet) {
      expect(f.textContent).toContain('Site profile version 7');
      expect(f.textContent).toContain(`catalogue ${view.version}`);
      expect(f.textContent).toContain(`gate policy ${fixtures.health.gate_policy_version}`);
      expect(f.textContent).toContain(`release ${fixtures.health.version}`);
      expect(f.textContent).toMatch(/exported \d+ \w+ \d{4}/);
      expect(f.textContent).not.toContain('Trial');
    }
    const stamp = screen.getByTestId('site-guide-stamp');
    expect(stamp).toHaveTextContent('Version 7, saved 26 Oct 2026');
    expect(stamp).toHaveTextContent("by Setup (the demo's answers)");
    expect(stamp).toHaveTextContent('This guide describes these versions only.');
  });

  it('describes every receiver of the profile, and the gate’s twelve checks with when each decides', async () => {
    renderGuide();
    const beds = await screen.findByTestId('site-guide-receiver-Downstream Out');
    expect(within(beds).getByText('What Shutter may do here')).toBeInTheDocument();
    expect(beds).toHaveTextContent('Overtaken failure: closes, no write.');
    expect(beds).toHaveTextContent('Shutter never sends it a cancel');
    expect(beds).toHaveTextContent('Shutter Approvers approve its writes');
    expect(screen.getByTestId('site-guide-receiver-Records Out')).toHaveTextContent(
      'Overtaken failure: asks a person to correct by hand.',
    );
    const checks = screen.getByRole('table', { name: "The gate's twelve checks" });
    expect(within(checks).getAllByRole('row')).toHaveLength(13);
    expect(checks).toHaveTextContent('Decides at the approval and at the dispatch');
    expect(screen.getByText('An unknown answer blocks a write, as a block does.')).toBeInTheDocument();
  });

  it('lists every shipped entry with who decides here, the outcome at each receiver and its scenario', async () => {
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    for (const e of catalogueView().shipped)
      expect(screen.getByTestId(`site-guide-entry-${e.id}`)).toBeInTheDocument();
    const e1 = screen.getByTestId('site-guide-entry-E1');
    expect(e1).toHaveTextContent('Who decides here: by site policy.');
    expect(e1).toHaveTextContent('At Downstream Out');
    expect(e1).toHaveTextContent('a correction of the history by a person (its alternative 1)');
    expect(e1).toHaveTextContent('Shown in the scenarios S1 (');
  });

  it("lists the trial's active sample entry as the site's own, and not the one waiting for a second person", async () => {
    renderGuide();
    const own = await screen.findByTestId('site-guide-entry-L1');
    expect(screen.getByText("This site's own entries")).toBeInTheDocument();
    expect(within(own).getByText("This site's own")).toBeInTheDocument();
    expect(own).toHaveTextContent('Version 1, approved by sample-approver, 15 Nov 2026');
    expect(screen.queryByTestId('site-guide-entry-L2')).toBeNull();
    expect(screen.getAllByTestId('site-guide-foot')[0]).toHaveTextContent(';g1:L1@1');
  });

  it("has no part for the site's own entries on a site with none", async () => {
    clearSiteEntries();
    renderGuide();
    await screen.findByTestId('site-guide-entry-E1');
    expect(screen.queryByText("This site's own entries")).toBeNull();
    expect(screen.getAllByTestId('site-guide-foot')[0]).not.toHaveTextContent(';g');
  });

  it("marks the site's own entries, with their instructions and who approved each and when", async () => {
    const example = SITE_ENTRIES_EXAMPLE.items[0];
    server.use(
      http.get('/api/shutter/catalogue', () =>
        HttpResponse.json({
          ...catalogueView(),
          version: `${catalogueView().version};g1:L1@1`,
          site: [
            {
              ...example.content,
              version: 1,
              origin: 'site',
              decides: 'person',
              preferred: { outcome: 'escalate', why: example.content!.why },
              alternatives: [],
              sentence: example.sentence,
            },
          ],
        }),
      ),
      http.get('/api/shutter/site-entries', () => HttpResponse.json(SITE_ENTRIES_EXAMPLE)),
    );
    renderGuide();
    const own = await screen.findByTestId('site-guide-entry-L1');
    expect(within(own).getByText("This site's own")).toBeInTheDocument();
    expect(own).toHaveTextContent(
      "Ring the ward's nurse in charge before anything is entered. Do not resend.",
    );
    expect(own).toHaveTextContent('Version 1, approved by approver, 15 Nov 2026');
    expect(own).toHaveTextContent('Who decides here: decided by a person.');
    expect(screen.getAllByTestId('site-guide-foot')[0]).toHaveTextContent(';g1:L1@1');
  });

  it('prints what an automatic release still sends to a person, as the route gives it, beside each release by policy', async () => {
    renderGuide();
    const beds = await screen.findByTestId('site-guide-receiver-Downstream Out');
    const holds = catalogueView().automaticHolds ?? [];
    expect(holds.map((h) => h.hold)).toContain('origin');
    expect(beds).toHaveTextContent(
      /Released automatically means the site's written policy releases the write after the gate and the dry run, unless .*: then an approver releases it\./,
    );
    for (const h of holds) expect(beds).toHaveTextContent(h.when);
    const e2 = screen.getByTestId('site-guide-entry-E2');
    expect(e2).toHaveTextContent(
      /Nobody is asked: the site's written policy releases the write after the gate and the dry run, unless /,
    );
    expect(e2).toHaveTextContent(
      "the case's source cannot be proved (feed.prove_origin): then an approver releases it.",
    );
  });

  it('reads the profile and the catalogue again when the catalogue was made under another profile version, and prints nothing meanwhile', async () => {
    let calls = 0;
    let release = () => {};
    const held = new Promise<void>((resolve) => (release = resolve));
    server.use(
      http.get('/api/shutter/catalogue', async () => {
        calls += 1;
        // The second read waits until the test has looked at the page meanwhile
        if (calls > 1) await held;
        return HttpResponse.json({ ...catalogueView(), profileVersion: calls === 1 ? 8 : 7 });
      }),
    );
    renderGuide();
    expect(
      (await screen.findAllByText('The site profile changed while the guide was read: reading it again…'))
        .length,
    ).toBeGreaterThan(0);
    expect(screen.queryByTestId('site-guide-stamp')).toBeNull();
    expect(screen.getByRole('button', { name: 'Print or save as PDF' })).toBeDisabled();
    release();
    expect(await screen.findByTestId('site-guide-stamp')).toHaveTextContent('Version 7');
    expect(screen.getByRole('button', { name: 'Print or save as PDF' })).toBeEnabled();
    expect(calls).toBe(2);
  });

  it('names who approved a site entry only for the version the catalogue lists', async () => {
    const example = SITE_ENTRIES_EXAMPLE.items[0];
    server.use(
      http.get('/api/shutter/catalogue', () =>
        HttpResponse.json({
          ...catalogueView(),
          site: [
            {
              ...example.content,
              version: 2,
              origin: 'site',
              decides: 'person',
              preferred: { outcome: 'escalate', why: example.content!.why },
              alternatives: [],
              sentence: example.sentence,
            },
          ],
        }),
      ),
      http.get('/api/shutter/site-entries', () =>
        HttpResponse.json({
          ...SITE_ENTRIES_EXAMPLE,
          items: [{ ...example, activeVersion: 3, approvedBy: 'bob' }],
        }),
      ),
    );
    renderGuide();
    const own = await screen.findByTestId('site-guide-entry-L1');
    expect(own).toHaveTextContent('Version 2; who approved it was not read.');
    expect(own).not.toHaveTextContent('bob');
  });

  it('lists the FHIR gate’s checks apart, with no dry run, where the profile has a FHIR receiver', async () => {
    const view = catalogueView();
    server.use(
      http.get('/api/shutter/site-profile', async () => {
        const recorded = structuredClone(fixtures.siteProfile) as unknown as {
          profile: { receivers: Record<string, unknown>[] };
        };
        recorded.profile.receivers.push({
          name: 'Ward FHIR',
          system: 'the ward system (FHIR R4)',
          category: 'current_state',
          tier: 3,
          fhir: { recovery_enabled: false, location_map: [] },
        });
        return HttpResponse.json(recorded);
      }),
      http.get('/api/shutter/catalogue', () => HttpResponse.json(view)),
    );
    renderGuide();
    expect(await screen.findByRole('heading', { name: 'At HL7 receivers' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'At FHIR receivers: Ward FHIR' })).toBeInTheDocument();
    const fhir = screen.getByRole('table', { name: "The FHIR gate's checks" });
    expect(fhir).toHaveTextContent('No dry run exists for this receiver. What stands in its place?');
    expect(fhir).not.toHaveTextContent("Did the receiver's dry run say this would apply?");
    expect(
      screen.getByText(
        /Substituted: a complete versioned read, a bounded change, If-Match on the version read/,
      ),
    ).toBeInTheDocument();
  });

  it('lists one gate table, with no receivers named, where the profile has no FHIR receiver', async () => {
    renderGuide();
    await screen.findByRole('table', { name: "The gate's twelve checks" });
    expect(screen.queryByRole('heading', { name: 'At HL7 receivers' })).toBeNull();
    expect(screen.queryByRole('table', { name: "The FHIR gate's checks" })).toBeNull();
  });

  it('shows the Technical names beside the plain words only in Technical', async () => {
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    expect(screen.queryByText('state_transition')).toBeNull();
    await userEvent.click(screen.getByRole('radio', { name: 'Technical' }));
    expect(screen.getByText('state_transition')).toBeInTheDocument();
    expect(screen.getAllByText('decides: policy').length).toBeGreaterThan(0);
  });

  it('prints from the toolbar and goes back to the Site profile', async () => {
    const print = vi.spyOn(window, 'print').mockImplementation(() => {});
    renderGuide();
    await screen.findByRole('heading', { level: 1 });
    await userEvent.click(screen.getByRole('button', { name: 'Print or save as PDF' }));
    expect(print).toHaveBeenCalledOnce();
    print.mockRestore();
    expect(screen.getByRole('link', { name: 'Site profile' })).toHaveAttribute('href', '/site-profile');
  });

  it('says what is missing when a reader may not read the profile, and writes nothing', async () => {
    const writes: string[] = [];
    server.events.on('request:start', ({ request }) => {
      if (request.method !== 'GET') writes.push(`${request.method} ${request.url}`);
    });
    server.use(
      http.get('/api/shutter/site-profile', () =>
        HttpResponse.json({ error: 'forbidden', detail: 'This needs Shutter_Operate' }, { status: 403 }),
      ),
    );
    renderGuide();
    expect(await screen.findByText('This guide needs the operator or approver role')).toBeInTheDocument();
    expect(writes).toEqual([]);
    server.events.removeAllListeners();
  });

  it('says what happens to a pattern no entry knows as the core does: the board, then a person only for a write', async () => {
    renderGuide();
    const scenarios = await part('site-guide-scenarios');
    expect(scenarios).not.toHaveTextContent('a pattern no entry knows goes to a person');
    expect(scenarios).toHaveTextContent(
      'a pattern no entry knows goes to the board: a plan that writes waits for a person, and one that sends nothing closes, flagged for a reviewer as a candidate entry.',
    );
  });

  it("says outside policy mode that the watched production's cases are settled by that mode, and asks nobody by policy", async () => {
    server.use(
      http.get('/api/shutter/settings', () =>
        HttpResponse.json({ ...fixtures.settings, watchedMode: 'board' }),
      ),
    );
    renderGuide();
    expect(await screen.findByTestId('site-guide-mode')).toHaveTextContent(
      "Failures from the watched production run in board mode here: the board of agents settles every case. The site's written policy releases no write in this mode",
    );
    for (const f of screen.getAllByTestId('site-guide-foot'))
      expect(f).toHaveTextContent('watched mode board');
    const scenarios = document.getElementById('site-guide-scenarios')!;
    expect(scenarios).not.toHaveTextContent('Nobody is asked');
    expect(scenarios).not.toHaveTextContent('An approver releases the write');
    expect(screen.getByTestId('site-guide-entry-E2')).toHaveTextContent(
      'Who decides here: the board of agents, as the watched mode asks.',
    );
  });

  it('prints in policy mode as before, with no mode line and no mode in the stamp', async () => {
    renderGuide();
    await screen.findByTestId('site-guide-stamp');
    expect(screen.queryByTestId('site-guide-mode')).toBeNull();
    for (const f of screen.getAllByTestId('site-guide-foot')) expect(f).not.toHaveTextContent('watched mode');
  });

  it('sends every case of a receiver with no recovery API to a person, and promises it no write', async () => {
    withProfile((p) =>
      p.receivers.push({
        name: 'Lab Old',
        system: 'the old lab system',
        category: 'current_state',
        tier: 3,
        features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
      }),
    );
    renderGuide();
    const scenarios = await part('site-guide-scenarios');
    expect(scenarios).toHaveTextContent(
      /At [^.]*Lab Old[^.]*, every case goes to a person with its findings, whatever the entry\./,
    );
    for (const e of within(scenarios).getAllByText(/^At /))
      if (e.textContent !== null && /every case goes to a person/.test(e.textContent) === false)
        expect(e.textContent).not.toContain('Lab Old');
  });

  it('names typed set-up answers in what reaches a model, by the site switch', async () => {
    withProfile((p) => (p.model_content = { free_text: false, setup_answers: true }));
    const on = renderGuide();
    const settings = await part('site-guide-settings');
    expect(settings).toHaveTextContent(
      "What a person types about a receiver in Set up the site goes to the model with that receiver's name and description, after the text rule refuses links, addresses, long numbers and secrets.",
    );
    on.unmount();
    server.resetHandlers();
    renderGuide();
    expect(await part('site-guide-settings')).toHaveTextContent(
      'Nothing typed in Set up the site is read by a model.',
    );
    await userEvent.click(screen.getByRole('radio', { name: 'Technical' }));
    expect(screen.getByText('model_content.free_text, model_content.setup_answers')).toBeInTheDocument();
  });

  it("says an outage resend leaves to a person a message whose case one of the site's own entries stopped", async () => {
    withProfile((p) =>
      Object.assign(p.receivers[0], { watch: { item: 'Downstream Out' }, engine_resend: true }),
    );
    renderGuide();
    expect(await screen.findByTestId('site-guide-receiver-Downstream Out')).toHaveTextContent(
      "After one approval the engine sends again the outage's messages that never arrived, settled by the receiver's declared duplicate handling, except a message whose case one of this site's own entries stopped: that goes to a person with the entry's instructions.",
    );
  });

  it("prints what holds for the site's own entries now: a suspension, a review, a lifted two-person rule", async () => {
    const warnings = [
      'Site entry L3 is suspended (by alice, 2026-11-16T09:00:00Z): its protection is off until a second person approves resuming it',
      'Site entry L1 needs review: an upgrade or a change of the site profile touched it. It still applies',
      'The two-person rule for site entries is lifted (by admin, 2026-11-16T09:30:00Z): one person may propose and approve their own entry',
    ];
    server.use(
      http.get('/api/shutter/site-entries', () =>
        HttpResponse.json({
          ...SITE_ENTRIES_EXAMPLE,
          status: {
            ...SITE_ENTRIES_EXAMPLE.status,
            suspended: ['L3'],
            needsReview: ['L1'],
            onePerson: { by: 'admin', at: '2026-11-16T09:30:00Z', reason: 'one approver on leave' },
            warnings,
          },
        }),
      ),
    );
    renderGuide();
    const list = await screen.findByTestId('site-guide-entry-warnings');
    for (const w of warnings) expect(list).toHaveTextContent(w);
    await userEvent.click(screen.getByRole('radio', { name: 'Technical' }));
    for (const w of warnings) expect(screen.getByTestId('site-guide-entry-warnings')).toHaveTextContent(w);
  });
});
