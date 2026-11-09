import { describe, expect, it } from 'vitest';
import { followedBoard, planLeader } from './follows';

describe('the board a case follows', () => {
  it('reads the leader from a follower plan only', () => {
    expect(planLeader('lead:C-000007')).toBe('C-000007');
    expect(planLeader('run:12')).toBe('');
    expect(planLeader(undefined)).toBe('');
  });

  it('names the leader while the case waits, and after it took the decision', () => {
    expect(followedBoard({ followsCase: 'C-000007' })?.note).toMatch(/^Waiting for its decision/);
    expect(followedBoard({ planCreatedBy: 'lead:C-000007' })).toEqual({
      caseId: 'C-000007',
      note: 'Took its decision; keeps its own gate and approval',
    });
  });

  it('names nobody for a case that follows no board, or fell to the rules', () => {
    expect(followedBoard({})).toBeNull();
    expect(followedBoard({ followsCase: '', planCreatedBy: 'rules' })).toBeNull();
  });
});
