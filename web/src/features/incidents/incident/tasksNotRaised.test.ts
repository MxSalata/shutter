import { describe, expect, it } from 'vitest';
import type { IncidentDetail, IncidentEvent, WorkflowTask } from '@/api/types';
import { notRaisedTitle, tasksNotRaised } from './tasksNotRaised';

const failed = (what: string, why = 'the target is not there'): IncidentEvent => ({
  at: '2026-11-06T09:00:00Z',
  kind: 'error',
  text: `No approval task could be raised for ${what}: nothing was released and no case failed. The error: ${why}.`,
  actor: 'system',
});
const task = (subject: string): WorkflowTask => ({
  taskId: '1',
  subject,
  actions: 'Approve,Reject',
  action: '',
  userName: '',
  role: 'Shutter Approvers',
  complete: false,
  assignedTo: '',
  timeCreated: '',
  timeCompleted: '',
});
const incident = (tasks: WorkflowTask[], state = 'awaiting_approval') =>
  ({ incidentId: 'I-000010', state, tasks }) as unknown as IncidentDetail;
const SHARED = task('Shutter I-000010: approve the release of 2 chain(s) to Downstream Out');

describe('the approval tasks that could not be raised', () => {
  it('finds none when every task was raised', () => {
    const inc = incident([
      SHARED,
      task('Shutter I-000010/3: approve the release of 1 chain(s) to Downstream Out'),
    ]);
    expect(
      tasksNotRaised(inc, [failed('incident I-000010'), failed('chain 3 of incident I-000010')]),
    ).toEqual([]);
  });

  it("finds a chain's own task beside the shared one, by its chain", () => {
    const missing = tasksNotRaised(incident([SHARED]), [failed('chain 3 of incident I-000010')]);
    expect(missing).toHaveLength(1);
    expect(missing[0].seq).toBe(3);
    expect(notRaisedTitle(missing)).toBe('Chain 3 of this incident is waiting for a person');
  });

  it('keeps the shared task apart from a chain of another incident number', () => {
    const inc = incident([task('Shutter I-0000101: approve the release of 1 chain(s) to Downstream Out')]);
    expect(tasksNotRaised(inc, [failed('incident I-000010')]).map((m) => m.seq)).toEqual([null]);
  });

  it('keeps the latest error for each task', () => {
    const missing = tasksNotRaised(incident([]), [
      failed('chain 2 of incident I-000010', 'no such role'),
      failed('chain 2 of incident I-000010', 'the item is disabled'),
    ]);
    expect(missing).toHaveLength(1);
    expect(missing[0].text).toContain('the item is disabled');
  });

  it('names every chain, the shared task first, and counts what it cannot list', () => {
    const events = [12, 3, 7, 1, 9, 4, 5].map((n) => failed(`chain ${n} of incident I-000010`));
    const missing = tasksNotRaised(incident([]), [...events, failed('incident I-000010')]);
    expect(missing.map((m) => m.seq)).toEqual([null, 1, 3, 4, 5, 7, 9, 12]);
    expect(notRaisedTitle(missing)).toBe(
      'This incident and its chains 1, 3, 4, 5, 7 and 2 more are waiting for a person',
    );
    expect(notRaisedTitle(missing.slice(1, 3))).toBe(
      'Chains 1 and 3 of this incident are waiting for a person',
    );
    expect(notRaisedTitle(missing.slice(0, 1))).toBe('This incident is waiting for a person');
  });

  it('says nothing for a closed incident, or for other errors', () => {
    expect(tasksNotRaised(incident([], 'closed'), [failed('incident I-000010')])).toEqual([]);
    const other = { ...failed('incident I-000010'), kind: 'note' };
    expect(
      tasksNotRaised(incident([]), [other, { ...other, kind: 'error', text: 'Something else' }]),
    ).toEqual([]);
  });
});
