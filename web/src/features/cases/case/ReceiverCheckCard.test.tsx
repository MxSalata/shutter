import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { api } from '@/api/client';
import type { ReceiverCheck } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { theme } from '@/theme';
import { layer1Words } from '@/test/words';
import { ReceiverCheckCard } from './ReceiverCheckCard';

const BASE = '/api/shutter';
let writes: string[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('operator');
  writes = [];
  server.events.removeAllListeners();
  server.events.on('request:start', ({ request }) => {
    if (request.method !== 'GET') writes.push(new URL(request.url).pathname);
  });
});

const MISSING = 'Not available from this message';

function document(): ReceiverCheck {
  return {
    caseId: 'C-000099',
    caseVersion: 3,
    snapshotId: '12',
    profileVersion: 2,
    guideVersion: '1',
    guideDigest: 'sha256:abc',
    variant: 'document',
    receiverEvidence: 'unavailable',
    evidenceNote: "Shutter cannot read this receiver's documents or reports.",
    receiverRead: null,
    identity: {
      patientId: 'MRN1',
      authority: 'HOSP',
      encounterId: 'No encounter supplied',
      receiver: 'Plain Docs Out',
      sourceSystem: 'DOCS',
      messageType: 'MDM^T02',
      controlId: 'DOC1',
      timeLabel: 'Message time',
      time: '2026-11-05 09:05:00 UTC',
      messageRef: '77',
      sourceRoute: MISSING,
      collectedAt: '2026-11-05 09:06:00 UTC',
    },
    messageRequest: {
      kind: 'T02',
      summary: 'File this document against the patient and episode named here.',
      note: '',
      fields: [
        { label: 'Document number', value: MISSING, source: 'unavailable' },
        { label: 'Document type', value: 'CN', source: 'message' },
      ],
    },
    laterMovement: null,
    queueWarning: 'Before correcting anything: check the queue. It may still arrive.',
    checks: [
      {
        id: 'document',
        where: 'The document list, and the rejected or unfiled queue if the site uses one.',
        compare: ['Document number', 'Whether it opens'],
        meanings: [
          { answer: 'present', label: 'Filed, and it opens', text: 'A person report.' },
          { answer: 'absent', label: 'Missing', text: 'Unresolved.' },
          { answer: 'different', label: 'Elsewhere', text: 'Unresolved too.' },
          { answer: 'cannot_tell', label: 'Cannot tell', text: 'Escalate.' },
        ],
      },
    ],
    siteRunbook: 'In Clinical Documents, check Filed and Unfiled.',
    unknown: ['Whether this document reached the receiver.'],
    limitations: ['This message contains more than one report or document item.'],
    report: "That stays a person's report.",
  };
}

function renderCard(caseId = 'C-000008') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <ReceiverCheckCard caseId={caseId} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const open = async () => {
  await userEvent.click(screen.getByRole('button', { name: 'What to check at the receiver' }));
  return screen.findByRole('region', { name: 'What to check at the receiver' });
};

describe('What to check at the receiver', () => {
  it('stays folded, and asks nothing of the server, until it is opened', async () => {
    let asked = 0;
    server.use(
      http.get(`${BASE}/cases/:id/receiver-check`, () => {
        asked += 1;
        return HttpResponse.json(document());
      }),
    );
    renderCard();
    expect(layer1Words(window.document.body).length).toBeLessThanOrEqual(6);
    expect(asked).toBe(0);
    await open();
    expect(asked).toBe(1);
  });

  it('shows the trial a recorded case: identity, what it asked, the queue, the checks, and no write', async () => {
    renderCard('C-000008');
    const card = await open();
    expect(await within(card).findByText('MRN1008')).toBeInTheDocument();
    expect(
      within(card).getByRole('heading', { name: 'What this message asked the receiver to record' }),
    ).toBeInTheDocument();
    expect(card).toHaveTextContent('Transfer to WARD-B');
    expect(card).toHaveTextContent('may still arrive');
    expect(card).toHaveTextContent('Never move the patient back');
    expect(card).toHaveTextContent('WARD-C');
    expect(card.textContent?.toLowerCase()).not.toMatch(/expected result|safe to resend/);
    expect(writes).toEqual([]);
  });

  it('says a value is missing in words, and labels the runbook as a hint', async () => {
    server.use(http.get(`${BASE}/cases/:id/receiver-check`, () => HttpResponse.json(document())));
    renderCard();
    const card = await open();
    expect((await within(card).findAllByText(MISSING)).length).toBeGreaterThan(0);
    expect(card).toHaveTextContent('Site runbook: a navigation hint, not evidence');
    expect(card).toHaveTextContent('In Clinical Documents, check Filed and Unfiled.');
    expect(card).toHaveTextContent('more than one report or document item');
  });

  it('holds to 400 words on every recorded variant', async () => {
    for (const id of ['C-000008', 'C-000011', 'C-000010', 'C-000016', 'C-000060', 'C-000055', 'C-000012']) {
      const { unmount } = renderCard(id);
      const card = await open();
      await within(card).findByRole('heading', { name: 'Where to look' });
      expect(layer1Words(card).length).toBeLessThanOrEqual(400);
      unmount();
    }
  });

  it('shows an error, not an empty card, when the route fails', async () => {
    server.use(
      http.get(`${BASE}/cases/:id/receiver-check`, () =>
        HttpResponse.json({ error: 'boom' }, { status: 500 }),
      ),
    );
    renderCard();
    const card = await open();
    expect(await within(card).findByRole('alert')).toBeInTheDocument();
  });

  it('is for a signed-in person, in the mock as on the server', async () => {
    resetMock(null);
    await expect(api.get('/cases/C-000008/receiver-check')).rejects.toMatchObject({ status: 401 });
  });

  it('answers 404 for a case that is not stopped', async () => {
    await expect(api.get('/cases/C-000001/receiver-check')).rejects.toMatchObject({ status: 404 });
  });
});
