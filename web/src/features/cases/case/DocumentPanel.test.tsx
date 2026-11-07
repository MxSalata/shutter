import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseDetail, CaseDocument } from '@/api/types';
import { theme } from '@/theme';
import { DocumentPanel } from './DocumentPanel';

function shown(document: CaseDocument) {
  const c = { document } as CaseDetail;
  return render(
    <MantineProvider theme={theme}>
      <DocumentPanel c={c} />
    </MantineProvider>,
  );
}

const usual: CaseDocument = {
  headline: 'Document delivery needs review. Shutter has sent nothing.',
  trigger: 'T02',
  document: { id: 'DOC-1^DMS', parent: '', completion: 'AU', confidentiality: 'U', availability: 'ZZ' },
  patient: {
    keys: [
      { id: 'MRN1', authority: 'HOSP', type: 'MR' },
      { id: '999', type: 'NH' },
    ],
  },
  delivery: { status: 'Error' },
  reasons: [{ code: 'DOC_CANCELLED', words: 'A cancellation names this document' }],
  chain: { complete: true, says: ['A cancellation (T11 at header 9, Error) names this document.'] },
};

const report: CaseDocument = {
  kind: 'report',
  headline: 'Report delivery needs review. Shutter has sent nothing.',
  trigger: 'R01',
  document: { id: 'REP-1^LAB', parent: '', completion: '', confidentiality: '', availability: '' },
  report: { placer: 'ORD-1^LAB', filler: 'REP-1^LAB', result_status: 'P', attachment: 'ED' },
  patient: { keys: [{ id: 'MRN1', authority: 'HOSP', type: 'MR' }] },
  delivery: { status: 'Error' },
  reasons: [
    {
      code: 'DOC_RESULT_STATUS_CHANGED',
      words: 'A further message for this order or report has another result status',
    },
  ],
  chain: {
    complete: true,
    says: [
      'A further message for this report (R01 at header 9, Error) has Final results (F); this one has Preliminary (P).',
    ],
  },
};

describe('DocumentPanel', () => {
  it('shows a report by its order, its report number and its result status, with no document rows', () => {
    const { container } = shown(report);
    expect(screen.getByText('REP-1^LAB')).toBeTruthy();
    expect(screen.getByText('ORD-1^LAB')).toBeTruthy();
    expect(screen.getByText('Preliminary (P)')).toBeTruthy();
    expect(screen.getByText('MRN1 HOSP MR')).toBeTruthy();
    expect(screen.getByText(/has Final results \(F\); this one has Preliminary \(P\)/)).toBeTruthy();
    expect(screen.getByText(/resends no report/)).toBeTruthy();
    expect(container.textContent).not.toContain('Availability');
    expect(container.textContent).not.toContain('Parent document');
  });

  it('says plainly when a report has no number', () => {
    shown({ ...report, report: { placer: '', filler: '', result_status: 'F', attachment: 'ED' } });
    expect(screen.getByText('No usable order or report number')).toBeTruthy();
  });

  it('calls TXA-19 CA what the standard calls it', () => {
    shown({ ...usual, document: { ...usual.document, availability: 'CA' } });
    expect(screen.getByText('Deleted (CA)')).toBeTruthy();
  });

  it('shows the identity, every patient identifier, the reasons and the chain, and says nothing was sent', () => {
    shown(usual);
    expect(screen.getByText('DOC-1^DMS')).toBeTruthy();
    expect(screen.getByText('MRN1 HOSP MR; 999 NH')).toBeTruthy();
    expect(screen.getByText('A cancellation names this document')).toBeTruthy();
    expect(screen.getByText(/T11 at header 9/)).toBeTruthy();
    expect(screen.getByText(/Shutter has sent nothing, and it resends no document/)).toBeTruthy();
  });

  it('never shows the positive code of a sender, whatever a block carries', () => {
    const { container } = shown(usual);
    expect(container.textContent).not.toContain('ELIGIBLE');
    expect(container.textContent).not.toContain('DOC_');
  });

  it('names a status the standard does not list rather than reading it as a known one', () => {
    shown(usual);
    expect(screen.getByText('ZZ, not a value the standard lists')).toBeTruthy();
    expect(screen.getByText('Usual control (U)')).toBeTruthy();
  });

  it('says plainly when a message has no document identifier', () => {
    shown({ ...usual, document: { ...usual.document, id: '' } });
    expect(screen.getByText('No usable document identifier')).toBeTruthy();
  });

  it('shows a restricted case no identity, with the statement for an authorised reviewer', () => {
    const { container } = shown({
      headline:
        'Restricted document delivery requires an authorised reviewer. No document content is shown or sent by email.',
      trigger: 'T02',
      restricted: true,
      identity_withheld: true,
      refusal: { ack_code: 'AE', text_withheld: true },
    });
    expect(screen.getByText(/requires an authorised reviewer/)).toBeTruthy();
    expect(screen.getByText('For an authorised reviewer')).toBeTruthy();
    expect(container.textContent).not.toContain('Patient identifiers');
    expect(container.textContent).not.toContain('Document ');
  });
});
