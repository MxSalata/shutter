import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactElement } from 'react';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { CaseEvent } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import CasePage from '../CasePage';
import { CaseTimeline } from './CaseTimeline';
import { EvidencePanel } from './EvidencePanel';
import { showEvidence } from './evidenceLinks';

// The trial's wording is chosen by the page's TRIAL flag, switched here per test (live unless a test says so)
const trial = vi.hoisted(() => ({ value: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return trial.value;
  },
}));

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'error' });
  // jsdom does not scroll; the tests watch what the page asks to scroll to
  if (!Element.prototype.scrollIntoView) Element.prototype.scrollIntoView = () => {};
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  trial.value = false;
});

/** Renders a piece of the case page with its data, a router and the Detail level (Plain unless said). */
function renderWith(
  ui: ReactElement,
  { detail = 'plain', path = '/' }: { detail?: DetailLevel; path?: string } = {},
) {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter(
    [
      { path: '/cases/:caseId', element: ui },
      { path: '*', element: ui },
    ],
    { initialEntries: [path] },
  );
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const evidence = (caseId: string, receiver = 'Downstream Out', detail: DetailLevel = 'plain') =>
  renderWith(<EvidencePanel caseId={caseId} receiver={receiver} open={false} />, { detail });

/** A section of the tab, by its heading, once the snapshot, the runs and the plan are read. */
const section = async (name: string) =>
  (await screen.findByRole('heading', { name, level: 3 })).closest('section') as HTMLElement;

/** The tab, once its snapshot is read and its citation lines are drawn. */
async function loaded() {
  const panel = await screen.findByRole('region', { name: 'Evidence' });
  await waitFor(() => expect(within(panel).getAllByText(/^Cited by /).length).toBeGreaterThan(0));
  return panel;
}

/** The words of a section's citation line. */
const citedBy = (el: HTMLElement) => el.querySelector('.evidence-citation')?.textContent;

/** An element's text as it reads, without what waits hidden in it (a term's definition for its tooltip). */
const visibleText = (el: HTMLElement) => {
  const copy = el.cloneNode(true) as HTMLElement;
  copy.querySelectorAll('[hidden]').forEach((h) => h.remove());
  return copy.textContent;
};

describe('the Evidence tab', () => {
  it('names its sections in the order the citations use, each with who cited it (C-000008)', async () => {
    evidence('C-000008');
    const panel = await loaded();
    expect(
      within(panel)
        .getAllByRole('heading', { level: 3 })
        .map((h) => h.textContent),
    ).toEqual([
      'The HL7 message',
      'Schema validation',
      'What the connector reported',
      'The failed operation',
      'The route and what the connector guarantees',
      "Downstream Out's encounter",
      "Downstream Out's receipt for this operation",
      'The operation timeline',
    ]);
    expect(citedBy(await section('The HL7 message'))).toBe('Cited by all three agents and the plan');
    // Encounter Integrity did not cite the schema validation: its ring is empty and its name is left out
    const validation = await section('Schema validation');
    expect(citedBy(validation)).toBe('Cited by Conformance, Impact Analysis and the plan');
    const marks = [...validation.querySelectorAll('.evidence-citation [data-member]')];
    expect(marks.map((m) => [m.getAttribute('data-member'), m.hasAttribute('data-hollow')])).toEqual([
      ['conformance', false],
      ['encounter', true],
      ['impact', false],
      ['coordinator', false],
    ]);
    expect(marks.every((m) => m.closest('[aria-hidden="true"]'))).toBe(true);
    expect(citedBy(await section('The operation timeline'))).toBe('Cited by all three agents and the plan');
  });

  it('sums up the HL7 message in a sentence, and keeps its segments in a data disclosure, open in Technical', async () => {
    evidence('C-000008');
    const message = await section('The HL7 message');
    // The sentence as it reads (a term's definition waits in the page for its tooltip)
    const sentence = [...message.querySelectorAll('p')].find((p) => p.textContent?.startsWith('ADT^A02'))!;
    expect(visibleText(sentence)).toBe(
      'ADT^A02 transfer of ENC-1008 to WARD-B, sent by PAS at 15 Oct, 09:20:00 BST.',
    );
    const toggle = within(message).getByRole('button', { name: 'The message, one segment per line' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    // Closed, its content stays in the page (inert until opened)
    const segments = message.querySelector<HTMLElement>('ul[aria-label="The message\'s segments"]')!;
    const lines = [...segments.querySelectorAll('li')].map((li) => li.textContent);
    expect(lines.map((l) => l?.slice(0, 3))).toEqual(['MSH', 'EVN', 'PID', 'PV1']);
    expect(lines[0]).toContain('MSH-9 ADT^A02 | MSH-10 MSG00802');
    expect(lines[3]).toContain('PV1-3 WARD-B^BAY2^04^HOSP | PV1-19 ENC-1008');
    // The patient's name stays out of it
    expect(segments).not.toHaveTextContent(/SYNTH/);
    // Out of the first layer until opened
    expect(layer1Words(message).join(' ')).not.toContain('MSH-9');
  });

  it('opens every data disclosure in Technical, and gives UTC beside each local time', async () => {
    evidence('C-000008', 'Downstream Out', 'technical');
    await loaded();
    const message = await section('The HL7 message');
    expect(
      within(message).getByRole('button', { name: 'The message, one segment per line' }),
    ).toHaveAttribute('aria-expanded', 'true');
    expect(
      within(message).getByRole('button', { name: 'The HL7 message: What was recorded' }),
    ).toHaveAttribute('aria-expanded', 'true');
    const panel = screen.getByRole('region', { name: 'Evidence' });
    expect(panel).toHaveTextContent(
      'Snapshot 1, taken 20 Oct, 18:27:03 BST, 17:27:03Z, with 7 observations.',
    );
    expect(within(message).getByText('Observed 20 Oct, 18:27:03 BST, 17:27:03Z')).toBeInTheDocument();
  });

  it('says what each observation found in plain words, every time with its date', async () => {
    evidence('C-000008');
    const panel = await loaded();
    expect(panel).toHaveTextContent('Snapshot 1, taken 20 Oct, 18:27:03 BST, with 7 observations.');
    expect(await section('The failed operation')).toHaveTextContent(
      'Transfer to WARD-B for ENC-1008, event time 15 Oct, 09:20:00 BST.',
    );
    const validation = await section('Schema validation');
    expect(within(validation).getByText('Valid')).toBeInTheDocument();
    expect(validation).toHaveTextContent('Parses as 2.5.1:ADT_A02 against the 2.5.1 schema.');
    expect(within(validation).getAllByText('2.5.1:ADT_A02')[0]).toHaveClass('code-chip');
    // The operation timeline keeps its table, the two transfers at the same time flagged
    const timeline = await section('The operation timeline');
    expect(within(timeline).getByRole('table')).toBeInTheDocument();
    expect(within(timeline).getAllByText('Same event time')).toHaveLength(2);
    expect(within(timeline).getAllByText(/^15 Oct, 09:20:00 BST$/).length).toBeGreaterThan(0);
  });

  it("opens the plan's words about the catalogue entry it cites", async () => {
    evidence('C-000008');
    await loaded();
    const chip = screen.getByLabelText('Catalogue entry E7: why the plan follows it');
    expect(chip).toHaveAttribute('aria-expanded', 'false');
    expect(chip).toHaveTextContent('E7');
    const entry = document.getElementById('evidence-catalogue-entry')!;
    expect(entry).not.toBeVisible();
    await userEvent.click(chip);
    expect(chip).toHaveAttribute('aria-expanded', 'true');
    expect(entry).toBeVisible();
    expect(entry).toHaveTextContent(/^Catalogue entry E7, version 2E7 matches: another source \(BEDMGR\)/);
  });

  it('shows later events as none when the snapshot found none and the plan cites them (C-000002)', async () => {
    evidence('C-000002');
    const later = await section('Later events');
    expect(later).toHaveTextContent('None: the snapshot found no later event for the encounter.');
    expect(citedBy(later)).toBe('Cited by the plan');
  });

  it('ends with the snapshot as the API sends it', async () => {
    evidence('C-000008');
    const panel = await loaded();
    const source = within(panel).getByText('As the API sends it').closest('button')!;
    expect(source).toHaveAttribute('aria-expanded', 'false');
    expect(within(panel).getByText('GET /api/shutter/cases/C-000008/snapshot')).toBeInTheDocument();
  });

  // The spec gives the tab no budget of its own: it holds to 400 words in Plain and 1.5 times that in Technical
  // (DESIGN 1.4), counting the words a reader reads; the shared count leaves out the JSON blocks open in Technical,
  // the machine's own text
  it.each(['C-000008', 'C-000058'])(
    'keeps %s to its word budget: 400 in Plain, 600 in Technical',
    async (caseId) => {
      const { unmount } = evidence(caseId);
      let panel = await loaded();
      expect(layer1Words(panel).length).toBeLessThanOrEqual(400);
      unmount();
      evidence(caseId, 'Downstream Out', 'technical');
      panel = await loaded();
      expect(layer1Words(panel).length).toBeLessThanOrEqual(600);
    },
  );

  it('says "live" nowhere in its first layer in the trial', async () => {
    trial.value = true;
    for (const caseId of ['C-000008', 'C-000058']) {
      const { unmount } = evidence(caseId);
      const panel = await screen.findByRole('region', { name: 'Evidence' });
      await waitFor(() => expect(within(panel).getAllByText(/^Cited by /).length).toBeGreaterThan(0));
      expect(layer1Words(panel).join(' ')).not.toMatch(/\blive\b/i);
      unmount();
    }
  });
});

describe('a citation, from anywhere on the case page', () => {
  it('switches to the Evidence tab, scrolls the section under the tab bar, opens what it recorded and focuses its heading', async () => {
    const scrolled: string[] = [];
    const scroll = vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(function (this: Element) {
      scrolled.push(this.id);
    });
    renderWith(<CasePage />, { path: '/cases/C-000008' });
    expect(await screen.findByRole('tab', { name: 'Summary' })).toHaveAttribute('aria-selected', 'true');
    act(() => showEvidence('validation'));
    expect(await screen.findByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    const heading = await screen.findByRole('heading', { name: 'Schema validation' });
    await waitFor(() => expect(heading).toHaveFocus());
    expect(scrolled).toContain('evidence-validation');
    const validation = heading.closest('section')!;
    expect(validation.style.scrollMarginTop).toContain('--shutter-header-h');
    expect(
      within(validation).getByRole('button', { name: 'Schema validation: What was recorded' }),
    ).toHaveAttribute('aria-expanded', 'true');
    // Only the cited section opens
    expect(screen.getByRole('button', { name: 'The HL7 message: What was recorded' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    // A catalogue entry lands on the line that names it
    act(() => showEvidence('catalogue:E7'));
    await waitFor(() => expect(document.getElementById('evidence-catalogue')).toHaveFocus());
    scroll.mockRestore();
  });
});

describe('the audit trail', () => {
  const recorded = fixtures.cases['C-000008'].events as unknown as CaseEvent[];

  it('says "Rationale as in the plan" for each event that repeats it, with the text one click away', async () => {
    renderWith(<CaseTimeline events={recorded} caseId="C-000008" />);
    const timeline = await screen.findByRole('region', { name: 'Timeline' });
    expect(within(timeline).getByText('Plan v1 (escalate). Rationale as in the plan.')).toBeInTheDocument();
    expect(
      within(timeline).getByText('The plan asks for a person. Rationale as in the plan.'),
    ).toBeInTheDocument();
    const toggles = within(timeline).getAllByRole('button', { name: "The plan's rationale" });
    expect(toggles).toHaveLength(2);
    expect(toggles.every((t) => t.getAttribute('aria-expanded') === 'false')).toBe(true);
    // The text stays on the page for a search, out of the first layer until opened
    expect(timeline).toHaveTextContent(/Escalate to a person to decide which source is authoritative\./);
    expect(layer1Words(timeline).join(' ')).not.toContain('supersession');
    // An event that says something of its own is shown whole
    expect(
      within(timeline).getByText(
        'Snapshot 1 taken: 7 observations, 0 later events, digest sha256:36d4b435753b',
      ),
    ).toBeInTheDocument();
  });

  it("dates every event that isn't today's, and gives today's its time alone", async () => {
    const now = new Date();
    now.setMilliseconds(0);
    const today: CaseEvent = { ...recorded[0], seq: 99, at: now.toISOString(), text: 'Noted today' };
    renderWith(<CaseTimeline events={[...recorded, today]} />);
    const timeline = await screen.findByRole('region', { name: 'Timeline' });
    const times = within(timeline)
      .getAllByRole('time')
      .map((t) => t.textContent);
    expect(times[0]).toBe('20 Oct, 18:26:48 BST');
    expect(times.at(-1)).toMatch(/^\d{2}:\d{2}:\d{2} (GMT|BST)$/);
  });

  it('marks the events the trial replays from the recording', async () => {
    const replayed = recorded.map((e, i) => (i >= recorded.length - 2 ? { ...e, replayed: true } : e));
    renderWith(<CaseTimeline events={replayed} />);
    const timeline = await screen.findByRole('region', { name: 'Timeline' });
    expect(within(timeline).getAllByText('Replayed')).toHaveLength(2);
  });

  it('ends with the events as the API sends them', async () => {
    renderWith(<CaseTimeline events={recorded} />, { path: '/cases/C-000008' });
    const timeline = await screen.findByRole('region', { name: 'Timeline' });
    expect(within(timeline).getByRole('button', { name: 'As the API sends it' })).toBeInTheDocument();
    expect(within(timeline).getByText('GET /api/shutter/cases/C-000008/events')).toBeInTheDocument();
  });

  it('reads the rationale once, and says "live" nowhere in its first layer in the trial', async () => {
    trial.value = true;
    renderWith(<CaseTimeline events={recorded} caseId="C-000008" />);
    const timeline = await screen.findByRole('region', { name: 'Timeline' });
    const words = layer1Words(timeline);
    // The rationale's 68 words are read once, on the Summary tab, not twice more here
    const rationale = fixtures.cases['C-000008'].plan.plan.summary;
    expect(words.join(' ')).not.toContain(rationale.split(/\s+/).slice(-8).join(' '));
    expect(words.length).toBeLessThanOrEqual(400);
    expect(words.join(' ')).not.toMatch(/\blive\b/i);
  });
});
