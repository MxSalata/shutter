import { MantineProvider } from '@mantine/core';
import { render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import type { CaseDetail } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { renderUi } from '@/test/render';
import { theme } from '@/theme';
import { CaseHeader } from './CaseHeader';

// The IRIS row asks the settings whether this is the online demo, which isn't what these tests are about
vi.mock('@/api/hooks', async (original) => ({
  ...(await original<typeof import('@/api/hooks')>()),
  useSettings: () => ({ data: undefined }),
}));

const base = { caseId: 'C-000123', state: 'resolved', event: 'transfer', ward: 'WARD-B' } as CaseDetail;

function renderHeader(c: CaseDetail) {
  return render(
    <MantineProvider theme={theme}>
      <MemoryRouter>
        <CaseHeader c={c} />
      </MemoryRouter>
    </MantineProvider>,
  );
}

describe('CaseHeader', () => {
  it('flags a case no catalogue entry fits', () => {
    renderHeader({ ...base, candidateEntry: true });
    expect(screen.getByText('New pattern')).toBeInTheDocument();
  });

  it('links a case to the incident that holds it, with its place in the chain', () => {
    renderHeader({
      ...base,
      incidentId: 'I-000001',
      incident: {
        incident_id: 'I-000001',
        incident_state: 'closed',
        chain_seq: 2,
        position: 1,
        chain_kind: 'ordered',
        item_state: 'resolved',
      },
    });
    expect(screen.getByRole('link', { name: 'I-000001' })).toHaveAttribute('href', '/incidents/I-000001');
    expect(screen.getByText('chain 2, item 1 · ordered · resolved')).toBeInTheDocument();
  });

  it('labels the disposition as a proposal, and shows an escalated state once', () => {
    const { unmount } = renderHeader({ ...base, state: 'blocked', disposition: 'resend' });
    expect(screen.getByText('Blocked')).toBeInTheDocument();
    expect(screen.getByText('Proposed: Resend')).toBeInTheDocument();
    unmount();
    renderHeader({ ...base, state: 'escalated', disposition: 'escalate' });
    expect(screen.getByText('Escalated')).toBeInTheDocument();
    expect(screen.queryByText(/Escalate$/)).not.toBeInTheDocument();
  });

  it('says nothing about the catalogue when an entry fits', () => {
    renderHeader({ ...base, candidateEntry: false });
    expect(screen.queryByText('New pattern')).not.toBeInTheDocument();
  });

  it("names where a forwarded case's message lives, and Shutter's own copy of it", () => {
    renderHeader({
      ...base,
      sourceHeaderId: '13111',
      sourceNamespace: 'HOSPITAL',
      sourceProduction: 'Hospital.Production',
      sourceRoute: 'PAS In',
      originHeaderId: '4243',
    });
    expect(screen.getByText('Source')).toBeInTheDocument();
    expect(
      screen.getByText(
        "Forwarded from HOSPITAL / Hospital.Production, route PAS In, message header 4243; Shutter's copy is message 13111",
      ),
    ).toBeInTheDocument();
  });

  it("names no source for a case the feed in Shutter's own production opened", () => {
    renderHeader({ ...base, sourceHeaderId: '11961', sourceNamespace: '', sourceProduction: '' });
    expect(screen.queryByText('Source')).not.toBeInTheDocument();
    expect(screen.queryByText(/^Forwarded from/)).not.toBeInTheDocument();
  });
});

describe('the case header status and IRIS row', () => {
  const recorded = fixtures.cases['C-000021'].detail as unknown as CaseDetail;
  const s8 = fixtures.scenarios.find((x) => x.id === 'S8') as never;
  const verified = { ...recorded, writes: 1, verification: 'verified' };

  it('puts the outcome first and the state after it, smaller, as one verdict and two facts', () => {
    renderUi(<CaseHeader c={verified} />);
    const outcome = screen.getByText('Delivered, verified');
    const state = screen.getByText('Resolved');
    expect(outcome.compareDocumentPosition(state) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(state.closest('.mantine-Badge-root')).toHaveAttribute('data-size', 'xs');
    expect(state.closest('.mantine-Badge-root')).toHaveAttribute('data-variant', 'outline');
    expect(outcome.closest('[data-tone]')).toHaveAttribute('data-tone', 'positive');
  });

  it("reads rules alone's S8 write as not as expected, with its scenario", () => {
    renderUi(<CaseHeader c={verified} scenario={s8} />);
    expect(screen.getByText('Not as expected').closest('[data-tone]')).toHaveAttribute(
      'data-tone',
      'blocking',
    );
    // In Plain the expectation mark is left to the outcome's own words
    expect(screen.getAllByText('Not as expected')).toHaveLength(1);
  });

  it("shows the case's message trace, workflow trace and source message in IRIS, always, with the guide's marks", () => {
    const { container } = renderUi(<CaseHeader c={recorded} portalBase="/csp/shutter/" />);
    const row = container.querySelector('[data-tour="case-iris"]') as HTMLElement;
    expect(row).toHaveTextContent(
      new RegExp(`^In IRIS:\\s*Message trace \\(session ${recorded.ensSessionId}\\)`),
    );
    const trace = within(row).getByRole('link', { name: /^Message trace/ });
    expect(trace).toHaveAttribute('href', recorded.links!.visualTrace);
    expect(trace).toHaveAttribute('data-tour-action', 'open-trace');
    // This case's workflow ran in the message's own session, so it is one trace and one link
    expect(recorded.workflowSessionId).toBe(recorded.ensSessionId);
    expect(within(row).queryByRole('link', { name: /^Workflow trace/ })).not.toBeInTheDocument();
    expect(within(row).getByRole('link', { name: /^Source message/ })).toHaveAttribute(
      'href',
      `/csp/shutter/EnsPortal.MessageContents.zen?HeaderId=${recorded.sourceHeaderId}`,
    );
    expect(row).toHaveTextContent(recorded.sourceMessageId!);
    // The record's other facts stay behind Details
    expect(screen.getByRole('button', { name: 'Details' })).toHaveAttribute('aria-expanded', 'false');
  });

  it('shows the workflow trace too when the workflow ran in a session of its own', () => {
    const { container } = renderUi(<CaseHeader c={{ ...recorded, workflowSessionId: '99999' }} />);
    const row = container.querySelector('[data-tour="case-iris"]') as HTMLElement;
    expect(within(row).getByRole('link', { name: /^Workflow trace/ })).toBeInTheDocument();
  });

  it("adds the expectation and the failure's code in Technical", () => {
    renderUi(<CaseHeader c={verified} scenario={s8} />, { detail: 'technical' });
    expect(screen.getAllByText('Not as expected')).toHaveLength(2);
    expect(screen.getByText('Failure')).toBeInTheDocument();
    expect(
      screen.getByText(`${recorded.failureHttpStatus} ${recorded.failureReasonCode}`),
    ).toBeInTheDocument();
  });

  it('leaves the failure code out of Plain, where the sentence says it', () => {
    renderUi(<CaseHeader c={verified} scenario={s8} />);
    expect(screen.queryByText('Failure')).not.toBeInTheDocument();
  });
});

describe('the case header facts: the patient and the message', () => {
  const recorded = (id: keyof typeof fixtures.cases) => fixtures.cases[id].detail as unknown as CaseDetail;
  const snapshot = (id: keyof typeof fixtures.cases) => fixtures.cases[id].snapshot as never;

  it("names the patient by the hospital number the message carries, and the message's HL7 type as IRIS parsed it", () => {
    renderUi(<CaseHeader c={recorded('C-000002')} snapshot={snapshot('C-000002')} />);
    const patient = screen.getByText('Patient').parentElement!;
    expect(patient).toHaveTextContent(/^PatientMRN1002$/);
    expect(screen.getByText('Message')).toBeInTheDocument();
    expect(screen.getByTestId('case-message-type')).toHaveTextContent(/^2\.5\.1:ADT_A02$/);
    // Never the patient's name, which the evidence holds
    expect(document.body).not.toHaveTextContent('SYNTH');
  });

  it("names a merge's structure as IRIS does: ADT^A40 parses as ADT_A39", () => {
    renderUi(<CaseHeader c={recorded('C-000012')} snapshot={snapshot('C-000012')} />);
    expect(screen.getByTestId('case-message-type')).toHaveTextContent('2.5.1:ADT_A39');
  });

  it('adds, in Technical, the version a message declares when the route parsed it as another', () => {
    const { unmount } = renderUi(<CaseHeader c={recorded('C-000050')} snapshot={snapshot('C-000050')} />);
    expect(screen.getByTestId('case-message-type')).toHaveTextContent('2.5.1:ADT_A02');
    expect(screen.queryByText('The message says HL7 2.4')).not.toBeInTheDocument();
    unmount();
    renderUi(<CaseHeader c={recorded('C-000050')} snapshot={snapshot('C-000050')} />, {
      detail: 'technical',
    });
    expect(screen.getByText('The message says HL7 2.4')).toBeInTheDocument();
  });

  it('falls back to MSH-9 and its version when the evidence names no document type', () => {
    const s = {
      ...fixtures.cases['C-000002'].snapshot,
      summary: {},
      items: [
        {
          seq: 1,
          kind: 'message',
          source: 'message_store',
          observed_at: '',
          data: { message_type: 'ADT^A03', message_version: '2.4' },
        },
      ],
    };
    renderUi(<CaseHeader c={recorded('C-000002')} snapshot={s as never} />);
    expect(screen.getByTestId('case-message-type')).toHaveTextContent('ADT^A03, HL7 2.4');
  });

  it('leaves out what is not known: no message before the evidence is read, no patient without an identifier', () => {
    renderUi(<CaseHeader c={{ ...recorded('C-000002'), patientId: '' }} />);
    expect(screen.queryByText('Patient')).not.toBeInTheDocument();
    expect(screen.queryByText('Message')).not.toBeInTheDocument();
    expect(screen.getByText('Receiver')).toBeInTheDocument();
  });
});
