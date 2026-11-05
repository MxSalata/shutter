import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { guideTarget } from '@/lib/guideDock';
import { useAppearance } from '@/stores/appearance';
import { theme } from '@/theme';
import CasePage from './CasePage';

/**
 * The case page made easier to read (a review of the trial, 2 Nov): where it failed, drawn; the patient and the
 * message's HL7 type in the header; the Outcome band smaller and collapsible; the progress strip's stages as links to
 * where each is told; and the case's action at the top and in the tab bar.
 */

const env = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => {
  const mode = await importOriginal<typeof import('@/env/mode')>();
  return {
    ...mode,
    get TRIAL() {
      return env.trial;
    },
  };
});

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function renderCase(caseId: string, query = '') {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/cases/:caseId', element: <CasePage /> }], {
    initialEntries: [`/cases/${caseId}${query}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const band = () => screen.findByRole('region', { name: 'Outcome' });
const toggle = async () => within(await band()).findByRole('button', { name: 'Outcome' });

beforeEach(() => {
  resetMock('approver');
  env.trial = false;
  window.localStorage.removeItem('shutter.outcomeBand');
  useAppearance.setState({ detail: 'plain' });
});

describe('where it failed', () => {
  it("draws the held S2 case's path as one image named by its sentence, with the same facts as a list", async () => {
    renderCase('C-000002');
    const picture = await screen.findByRole('img', {
      name: 'Where it failed: PAS sent the transfer to WARD-B through IRIS to the bed-management system: not delivered, answered HTTP 503 ward_unavailable. Shutter picked up the failure; now waiting for approval.',
    });
    expect(picture).toHaveTextContent('Not delivered');
    expect(picture).toHaveTextContent('HTTP 503 ward_unavailable');
    expect(picture).toHaveTextContent('Bed-management system');
    // Plain leaves the route's items to Technical
    expect(picture).not.toHaveTextContent('ADT to Downstream');
    const steps = within(screen.getByTestId('failure-map')).getAllByRole('listitem', { hidden: true });
    expect(steps.map((s) => s.textContent)).toEqual([
      'Sender: PAS, the patient administration system, sent the transfer to WARD-B.',
      'IRIS, the message engine.',
      'Receiver: the bed-management system, not delivered, answered HTTP 503 ward_unavailable.',
      'Shutter picked up the failure; now waiting for approval.',
    ]);
  });

  it("adds the route's items, the event's HL7 type and the reason code in Technical", async () => {
    useAppearance.setState({ detail: 'technical' });
    renderCase('C-000064');
    const picture = await screen.findByRole('img', { name: /^Where it failed: / });
    await waitFor(() => expect(picture).toHaveTextContent('ADT In → ADT to Downstream → Downstream Out'));
    expect(picture).toHaveTextContent('ADT^A02');
    expect(picture).toHaveTextContent('Downstream Out · /downstream/api');
    expect(picture).toHaveTextContent("Its schema couldn't read the message");
    await waitFor(() => expect(picture).toHaveTextContent('PARSE_FAILED'));
    expect(picture).toHaveTextContent('Blocked: nothing sent');
  });
});

describe("the header's patient and message", () => {
  it('names the patient by hospital number and the message as IRIS typed it, from the evidence', async () => {
    renderCase('C-000008');
    expect(await screen.findByTestId('case-message-type')).toHaveTextContent('2.5.1:ADT_A02');
    // The header's fact: its label over its value, as the other facts of the line
    expect(
      screen.getAllByText('Patient').some((el) => el.nextElementSibling?.textContent === 'MRN1008'),
    ).toBe(true);
  });
});

describe('the Outcome band', () => {
  it('starts open on a case that needs a person, its cards and receipt in view, the versions closed', async () => {
    renderCase('C-000008');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    const top = await band();
    expect(within(top).getByRole('heading', { name: 'What needs you now' })).toBeVisible();
    expect(within(top).getByRole('heading', { name: 'Decision receipt' })).toBeVisible();
    expect(within(top).getByRole('button', { name: 'Versions, keys and times' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });

  it('keeps the versions closed in Technical too, a click away', async () => {
    useAppearance.setState({ detail: 'technical' });
    renderCase('C-000008');
    expect(
      await within(await band()).findByRole('button', { name: 'Versions, keys and times' }),
    ).toHaveAttribute('aria-expanded', 'false');
  });

  it('starts closed on a closed case, still saying the outcome in one line', async () => {
    renderCase('C-000058');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'false');
    await waitFor(() =>
      expect(screen.getByTestId('outcome-line')).toHaveTextContent('Delivered: verified at the receiver'),
    );
    expect(screen.getByTestId('outcome-line')).toBeVisible();
    expect(
      within(await band()).queryByRole('heading', { name: 'What needs you now' }),
    ).not.toBeInTheDocument();
  });

  it("remembers the reader's choice for that kind of case, and leaves the other kind's default", async () => {
    const { unmount } = renderCase('C-000058');
    await userEvent.click(await toggle());
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    expect(JSON.parse(window.localStorage.getItem('shutter.outcomeBand')!)).toEqual({ closed: true });
    unmount();
    const again = renderCase('C-000021');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    again.unmount();
    renderCase('C-000008');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    await userEvent.click(await toggle());
    expect(await toggle()).toHaveAttribute('aria-expanded', 'false');
    expect(JSON.parse(window.localStorage.getItem('shutter.outcomeBand')!)).toEqual({
      closed: true,
      needs: false,
    });
  });

  it('opens and closes when storage refuses to be read or written', async () => {
    const get = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('denied');
    });
    const set = vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('denied');
    });
    renderCase('C-000058');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(await toggle());
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    get.mockRestore();
    set.mockRestore();
  });

  it('opens while the guide points at it or at the receipt', async () => {
    renderCase('C-000058');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'false');
    act(() => guideTarget.set('case-receipt'));
    await waitFor(async () => expect(await toggle()).toHaveAttribute('aria-expanded', 'true'));
    act(() => guideTarget.set(null));
  });

  it("keeps a long next action short, its rest behind the card's details", async () => {
    renderCase('C-000064');
    const top = await band();
    const card = (await within(top).findByRole('heading', { name: 'What needs you now' })).closest(
      '.story-card',
    ) as HTMLElement;
    await within(card).findByText("Read the gate's words.");
    expect(within(card).queryByTestId('next-action-rest')).not.toBeInTheDocument();
    await userEvent.click(within(card).getByRole('button', { name: 'Why, and what to do' }));
    expect(within(card).getByTestId('next-action-rest')).toHaveTextContent(
      /^When the second parser reads the message as sound/,
    );
  });
});

describe("the case's action", () => {
  it('asks the approver to decide on the held resend, in the attention tone, at the top and in the tab bar', async () => {
    renderCase('C-000002');
    const top = await screen.findByTestId('case-action');
    await waitFor(() => expect(top).toHaveAccessibleName('Needs you: decide on the resend'));
    expect(top).toHaveTextContent('Decide on the resend');
    expect(top).toHaveAttribute('data-variant', 'light');
    expect(top).toHaveAttribute('data-needs-you', 'true');
    expect(top).not.toBeDisabled();
    const compact = screen.getByTestId('case-action-compact');
    expect(compact).toHaveAccessibleName('Needs you: decide on the resend');
    expect(compact).toHaveTextContent('Needs you');
    // The copy sits with the tabs, outside the tab list
    expect(compact.closest('.case-tab-bar')).not.toBeNull();
    expect(compact.closest('[role="tablist"]')).toBeNull();
  });

  it('tells an operator that the held resend waits for an approver, quietly', async () => {
    resetMock('operator');
    renderCase('C-000002');
    const top = await screen.findByTestId('case-action');
    await waitFor(() => expect(top).toHaveAccessibleName('No action for you: waiting for an approver'));
    expect(top).toHaveAttribute('data-variant', 'default');
    expect(top).not.toHaveAttribute('data-needs-you');
  });

  it('says no action is needed on a closed case, and still takes the reader to the card, opening the band', async () => {
    renderCase('C-000058');
    expect(await toggle()).toHaveAttribute('aria-expanded', 'false');
    const action = await screen.findByTestId('case-action');
    expect(action).toHaveAccessibleName('No action needed on this case');
    await userEvent.click(action);
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
    await waitFor(() => expect(document.activeElement).toHaveAccessibleName('What needs you now'));
  });

  it('takes the reader to the Escalations panel when escalating is the action', async () => {
    renderCase('C-000064');
    const action = await screen.findByTestId('case-action');
    await waitFor(() => expect(action).toHaveAccessibleName('Needs you: escalate to a team'));
    await userEvent.click(action);
    await waitFor(() => expect(document.activeElement?.id).toBe('escalations-title'));
  });

  it('takes the approver to the Approval section, where Approve and Reject are', async () => {
    renderCase('C-000002');
    const action = await screen.findByTestId('case-action');
    await waitFor(() => expect(action).toHaveAccessibleName('Needs you: decide on the resend'));
    await userEvent.click(action);
    await waitFor(() => expect(document.activeElement?.id).toBe('approval-title'));
  });

  it("still opens the card's details for a reader whose action has no place of its own", async () => {
    resetMock('operator');
    renderCase('C-000002');
    const action = await screen.findByTestId('case-action');
    await waitFor(() => expect(action).toHaveAccessibleName('No action for you: waiting for an approver'));
    await userEvent.click(action);
    await waitFor(() => expect(document.activeElement?.id).toBe('next-action-title'));
  });

  it('works from the copy in the tab bar too', async () => {
    renderCase('C-000058');
    await toggle();
    await userEvent.click(screen.getByTestId('case-action-compact'));
    expect(await toggle()).toHaveAttribute('aria-expanded', 'true');
  });
});

describe('the progress strip', () => {
  it('makes each stage the case reached a button to where the page tells it; a stage not reached is text', async () => {
    renderCase('C-000002');
    const progress = await screen.findByLabelText("The case's progress");
    const evidence = await within(progress).findByRole('button', {
      name: 'Evidence: done, show the evidence',
    });
    expect(
      within(progress).getByRole('button', { name: 'Investigation: done, show the board' }),
    ).toBeInTheDocument();
    expect(
      within(progress).getByRole('button', { name: 'Approval: waiting for approval, show the approval' }),
    ).toBeInTheDocument();
    expect(within(progress).queryByRole('button', { name: /^Dispatch/ })).not.toBeInTheDocument();
    expect(within(progress).getByText('Dispatch')).toBeInTheDocument();
    await userEvent.click(evidence);
    expect(await screen.findByRole('tab', { name: 'Evidence' })).toHaveAttribute('aria-selected', 'true');
    await waitFor(() => expect(document.activeElement?.id).toBe('evidence-title'));
  });

  it('opens the story step a stage is told in, and focuses its section', async () => {
    renderCase('C-000064');
    const progress = await screen.findByLabelText("The case's progress");
    await userEvent.click(
      await within(progress).findByRole('button', {
        name: 'Plan and gate: stopped here, show the plan and the gate',
      }),
    );
    expect(await screen.findByRole('button', { name: /^4\. Gate and decision/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    await waitFor(() => expect(document.activeElement?.id).toBe('gate-title'));
  });

  it('names the investigation for what it shows on a case with no board on top', async () => {
    renderCase('C-000064');
    const progress = await screen.findByLabelText("The case's progress");
    await userEvent.click(
      await within(progress).findByRole('button', { name: 'Investigation: done, show the investigation' }),
    );
    expect(await screen.findByRole('button', { name: /^3\. What was proposed/ })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });
});
