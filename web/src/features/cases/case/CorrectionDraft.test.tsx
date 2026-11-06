import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { CorrectionDraftView, CorrectionSteps } from '@/api/types';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { renderUi } from '@/test/render';
import { layer1Words } from '@/test/words';
import { CorrectionDraft } from './CorrectionDraft';
import {
  CANCEL_TEXT,
  CANCELS_FALSE,
  DRAWN_DRAFT,
  DRAWN_SEQUENCE,
  REPLAY_B_TEXT,
  STOPPED_DRAFT,
} from './correctionDraft.fixture';

const ROUTE = '/api/shutter/cases/C-000055/correction-draft';
const correction = (sequence?: CorrectionSteps['sequence']): CorrectionSteps => ({
  receiver: 'Records Out',
  steps: ['Hold the case.'],
  sequence,
});

/** The route's answers in turn (the last repeats), and how many reads reached it. */
function draftRoute(...answers: (CorrectionDraftView | { status: number; body: object })[]) {
  const seen = { reads: 0 };
  server.use(
    http.get(ROUTE, () => {
      const answer = answers[Math.min(seen.reads, answers.length - 1)];
      seen.reads += 1;
      return 'status' in answer
        ? HttpResponse.json(answer.body, { status: answer.status })
        : HttpResponse.json(answer);
    }),
  );
  return seen;
}

function renderBlock(sequence?: CorrectionSteps['sequence']) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return renderUi(
    <QueryClientProvider client={client}>
      <CorrectionDraft caseId="C-000055" correction={correction(sequence)} />
    </QueryClientProvider>,
  );
}

const readButton = () => screen.findByRole('button', { name: 'Read the messages' });

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  vi.restoreAllMocks();
});
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

describe('the drafted sequence on the case', () => {
  it('shows nothing for a plan from before the sequence', () => {
    const { container } = renderBlock(undefined);
    expect(container.querySelector('[data-testid="correction-draft"]')).toBeNull();
  });

  it('says why no sequence is drawn, and offers nothing to read', async () => {
    const route = draftRoute(DRAWN_DRAFT);
    renderBlock(CANCELS_FALSE);
    expect(screen.getByTestId('correction-draft-none')).toHaveTextContent(
      /^No sequence: the receiver's entry says it takes no cancels/,
    );
    expect(screen.queryByTestId('correction-draft-structure')).not.toBeInTheDocument();
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(screen.queryByRole('button', { name: 'Read the messages' })).not.toBeInTheDocument();
    expect(route.reads).toBe(0);
  });

  it('shows an operator the structure and no way to the text', async () => {
    resetMock('operator');
    const route = draftRoute(DRAWN_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    expect(await screen.findByTestId('correction-draft-ask')).toHaveTextContent('ask one');
    const items = within(screen.getByTestId('correction-draft-structure')).getAllByRole('listitem');
    expect(items).toHaveLength(3);
    expect(items[0]).toHaveTextContent('Cancel (A12): the transfer to WARD-C at 2026-10-16T09:45:00Z.');
    expect(items[0]).toHaveTextContent(
      'After it, by the source: WARD-B. By what this receiver holds: WARD-A.',
    );
    expect(items[1]).toHaveTextContent(
      'Replay, unchanged (A02): the transfer to WARD-B at 2026-10-16T09:20:00Z, control id MSG02202.',
    );
    expect(screen.queryByRole('button', { name: /Read/ })).not.toBeInTheDocument();
    expect(screen.getByTestId('correction-draft')).not.toHaveTextContent('MSH|');
    expect(route.reads).toBe(0);
  });

  it('reads nothing for an approver until they ask, since each read is recorded', async () => {
    const route = draftRoute(DRAWN_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    expect(await readButton()).toBeEnabled();
    await new Promise((resolve) => setTimeout(resolve, 50));
    expect(route.reads).toBe(0);
    expect(screen.getByTestId('correction-draft')).not.toHaveTextContent('MSH|');
    expect(screen.getByTestId('correction-draft')).toHaveTextContent('Each read is recorded on the case.');
  });

  it('gives an approver the header, each message with its own Copy, what it cannot know and the never list', async () => {
    const route = draftRoute(DRAWN_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    const header = await screen.findByTestId('correction-draft-header');
    expect(header.children).toHaveLength(9);
    expect(header.children[0]).toHaveTextContent(
      'Draft. Shutter has sent none of this and will send none of it.',
    );
    for (const n of [1, 2, 3]) {
      const message = screen.getByTestId(`correction-message-${n}`);
      expect(within(message).getByRole('heading')).toHaveTextContent(`Message ${n} of 3`);
      expect(within(message).getByRole('button', { name: `Copy message ${n}` })).toBeInTheDocument();
      expect(message.querySelector('pre')).toHaveTextContent('MSH|');
    }
    expect(screen.getByRole('table')).toBeInTheDocument();
    expect(within(screen.getByRole('table')).getAllByRole('row')).toHaveLength(11);
    expect(screen.getByText(/^Never use Z99/)).toBeInTheDocument();
    // The structure gives way to the text, and the one way to send anything stays a person's own
    expect(screen.queryByTestId('correction-draft-structure')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /send/i })).not.toBeInTheDocument();
    expect(route.reads).toBe(1);
  });

  it('breaks the lines on the page and copies the message exactly, carriage returns included', async () => {
    draftRoute(DRAWN_DRAFT);
    const user = userEvent.setup();
    renderBlock(DRAWN_SEQUENCE);
    await user.click(await readButton());
    const second = await screen.findByTestId('correction-message-2');
    expect(second.querySelector('pre')!.textContent).toBe(REPLAY_B_TEXT.replace(/\r/g, '\n').trimEnd());
    await user.click(within(second).getByRole('button', { name: 'Copy message 2' }));
    expect(await within(second).findByRole('button', { name: 'Copied message 2' })).toBeInTheDocument();
    expect(await navigator.clipboard.readText()).toBe(REPLAY_B_TEXT);
  });

  it('says a cancel has values for the sender to fill, and a replay has none', async () => {
    draftRoute(DRAWN_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    expect(await screen.findByTestId('correction-message-1')).toHaveTextContent(
      'The values in square brackets are for the person sending to fill in.',
    );
    expect(screen.getByTestId('correction-message-1').querySelector('pre')).toHaveTextContent(
      '[SENDER: new control id]',
    );
    expect(CANCEL_TEXT).toContain('[SITE: event time for a cancel]');
    expect(screen.getByTestId('correction-message-2')).not.toHaveTextContent('square brackets');
  });

  it('says so when the browser refuses the copy, so the last message is not pasted by mistake', async () => {
    draftRoute(DRAWN_DRAFT);
    const user = userEvent.setup();
    renderBlock(DRAWN_SEQUENCE);
    vi.spyOn(navigator.clipboard, 'writeText').mockRejectedValue(new Error('refused'));
    await user.click(await readButton());
    const first = await screen.findByTestId('correction-message-1');
    await user.click(within(first).getByRole('button', { name: 'Copy message 1' }));
    expect(await within(first).findByTestId('correction-copy-failed')).toHaveTextContent('select the text');
    expect(within(first).queryByRole('button', { name: /^Copied/ })).not.toBeInTheDocument();
  });

  it('holds back a message above ASCII with no text and no Copy, and leaves the others', async () => {
    const withheld =
      "Don't paste this message: resend it from the message store (control id MSG02202), because the copy here may not match the bytes sent.";
    draftRoute({
      ...DRAWN_DRAFT,
      messages: DRAWN_DRAFT.messages.map((m) => (m.n === 2 ? { ...m, text: null, withheld } : m)),
    });
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    const second = await screen.findByTestId('correction-message-2');
    expect(within(second).getByTestId('correction-message-withheld')).toHaveTextContent(withheld);
    expect(second.querySelector('pre')).toBeNull();
    expect(within(second).queryByRole('button', { name: /Copy/ })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy message 3' })).toBeInTheDocument();
  });

  it('shows a cancel carrying the copied PID with the warning, and no Copy beside "Don\'t paste"', async () => {
    const withheld = "Don't paste this message: the copy here may not match the bytes sent.";
    draftRoute({
      ...DRAWN_DRAFT,
      messages: DRAWN_DRAFT.messages.map((m) => (m.n === 1 ? { ...m, withheld } : m)),
    });
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    const first = await screen.findByTestId('correction-message-1');
    expect(first.querySelector('pre')).toHaveTextContent('ADT^A12');
    expect(within(first).queryByRole('button', { name: /Copy/ })).not.toBeInTheDocument();
  });

  it('takes the text away when a read finds a further message, and says what it found', async () => {
    const route = draftRoute(DRAWN_DRAFT, STOPPED_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    await screen.findByTestId('correction-message-1');
    await userEvent.click(screen.getByRole('button', { name: 'Read it again' }));
    const stopped = await screen.findByTestId('correction-draft-stopped');
    expect(stopped).toHaveTextContent('This draft no longer stands.');
    expect(stopped).toHaveTextContent('admit on encounter ENC-2044');
    expect(screen.getByTestId('correction-draft')).not.toHaveTextContent('MSH|');
    expect(screen.queryByRole('button', { name: /Copy/ })).not.toBeInTheDocument();
    expect(screen.queryByTestId('correction-draft-structure')).not.toBeInTheDocument();
    expect(route.reads).toBe(2);
  });

  it('wins over the plan on the first read too', async () => {
    draftRoute(STOPPED_DRAFT);
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    expect(await screen.findByTestId('correction-draft-stopped')).toBeInTheDocument();
    expect(screen.queryByTestId('correction-draft-header')).not.toBeInTheDocument();
  });

  it("shows the server's refusal and no text", async () => {
    draftRoute({ status: 403, body: { error: 'forbidden', detail: 'This needs Shutter_Approve' } });
    renderBlock(DRAWN_SEQUENCE);
    await userEvent.click(await readButton());
    expect(await screen.findByRole('alert')).toHaveTextContent('The draft could not be read');
    expect(screen.getByTestId('correction-draft')).not.toHaveTextContent('MSH|');
  });

  // The block opens behind the card's details, so the case page's Summary budget (640 words, steps closed) doesn't pay
  // for it. Its own ceilings, in Plain: the no-sequence line, then the structure for one later movement. The text an
  // approver asks for is not first-layer reading, and its words are the server's. Measured: 189 for three messages.
  it('keeps its first layer within its word budget', async () => {
    resetMock('operator');
    const none = renderBlock(CANCELS_FALSE);
    expect(layer1Words(none.container).length).toBeLessThanOrEqual(35);
    none.unmount();
    const drawn = renderBlock(DRAWN_SEQUENCE);
    await screen.findByTestId('correction-draft-ask');
    expect(layer1Words(drawn.container).length).toBeLessThanOrEqual(190);
  });
});
