import { describe, expect, it } from 'vitest';
import type { CaseDetail, Snapshot } from '@/api/types';
import { approvalChange } from './approvalChange';

const c = { event: 'transfer', ward: 'WARD-B' } as CaseDetail;
const snapshot = (ward_state: unknown) =>
  ({ takenAt: '2026-11-02T14:16:40Z', summary: { ward_state } }) as unknown as Snapshot;

describe("the approval dialog's before and after", () => {
  it('says what the receiver held, when it was read, and what the write would make it, on its condition', () => {
    expect(approvalChange(c, 1, snapshot({ ward: 'WARD-A', version: 1 }))).toEqual({
      before: 'WARD-A at version 1',
      readAt: '2026-11-02T14:16:40Z',
      after: 'WARD-B, only if the receiver is still at version 1 when it is read again',
    });
  });

  it('names the state where the receiver holds no ward, and the event where the message names none', () => {
    const r = approvalChange(
      { event: 'discharge', ward: '' } as CaseDetail,
      3,
      snapshot({ state: 'admitted', version: 3 }),
    );
    expect(r.before).toBe('Admitted at version 3');
    expect(r.after).toMatch(/^Discharge applied, only if the receiver is still at version 3/);
  });

  it('flags a before it does not have, rather than leave it out', () => {
    expect(approvalChange(c, 1, undefined).before).toBe('Not read yet');
    expect(approvalChange(c, 1, null).before).toBe('Not in the evidence');
    const empty = approvalChange(c, 1, snapshot({}));
    expect(empty.before).toBe('Not in the evidence');
    expect(empty.readAt).toBe('');
  });
});
