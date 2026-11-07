import { describe, expect, it } from 'vitest';
import type { CaseDetail, Snapshot } from '@/api/types';
import { approvalChange } from './approvalChange';

const c = { event: 'transfer', ward: 'WARD-B' } as CaseDetail;
const snapshot = (ward_state: unknown) =>
  ({ takenAt: '2026-11-02T14:16:40Z', summary: { ward_state } }) as unknown as Snapshot;

describe("the approval dialog's reading and after", () => {
  it('says what the evidence read at the receiver, when, and what the write would make it', () => {
    expect(approvalChange(c, snapshot({ ward: 'WARD-A', version: 1 }))).toEqual({
      held: 'WARD-A at version 1',
      readAt: '2026-11-02T14:16:40Z',
      after: 'WARD-B',
    });
  });

  it('names the state where the receiver holds no ward, and the event where the message names none', () => {
    const r = approvalChange(
      { event: 'discharge', ward: '' } as CaseDetail,
      snapshot({ state: 'admitted', version: 3 }),
    );
    expect(r.held).toBe('Admitted at version 3');
    expect(r.after).toBe('Discharge applied');
  });

  it('flags a reading it does not have, rather than leave it out', () => {
    expect(approvalChange(c, undefined).held).toBe('Not read yet');
    expect(approvalChange(c, null).held).toBe('Not in the evidence');
    const empty = approvalChange(c, snapshot({}));
    expect(empty.held).toBe('Not in the evidence');
    expect(empty.readAt).toBe('');
  });
});
