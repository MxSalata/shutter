import { describe, expect, it } from 'vitest';
import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { readBehind, replacedWords, whatChanged, type ReviewedState } from './staleReview';

const recorded = fixtures.cases['C-000002'] as unknown as {
  detail: CaseDetail;
  plan: PlanView;
  snapshot: Snapshot;
};

/** The held S2 case as a review opened on it: plan v1, the receiver at version 1, the case at version 6. */
function opened(): ReviewedState {
  return {
    c: { ...recorded.detail, state: 'awaiting_approval', version: 6 },
    view: recorded.plan,
    snapshot: recorded.snapshot,
  };
}

/** The same case re-planned: the receiver moved the patient's bed (version 2) and plan v2 is conditional on it. */
function replanned(): ReviewedState {
  const before = opened();
  const summary = before.snapshot!.summary as { ward_state: Record<string, unknown> };
  return {
    c: { ...before.c, version: 9 },
    view: {
      ...before.view,
      plan: { ...before.view.plan, version: 2, digest: 'sha256:2b', expectedVersion: 2 },
    },
    snapshot: {
      ...before.snapshot!,
      digest: 'sha256:snap2',
      materialDigest: 'sha256:mat2',
      summary: { ...summary, ward_state: { ...summary.ward_state, bed: 'BAY1-03', version: 2 } },
    },
  };
}

const byLabel = (rows: ReturnType<typeof whatChanged>) => Object.fromEntries(rows.map((r) => [r.label, r]));

describe('what changed under a stopped review', () => {
  it('compares the plan, its action, the receiver version, the evidence and the case version', () => {
    const rows = byLabel(whatChanged(opened(), replanned()));
    expect(Object.keys(rows)).toEqual(['Plan', 'Action', 'Receiver version', 'Evidence', 'Case version']);
    expect(rows.Plan).toEqual({ label: 'Plan', was: 'v1', now: 'v2', changed: true });
    expect(rows.Action).toMatchObject({ was: 'Resend the PAS transfer to WARD-B, once', changed: false });
    expect(rows['Receiver version']).toEqual({
      label: 'Receiver version',
      was: '1',
      now: '2',
      changed: true,
    });
    expect(rows.Evidence).toEqual({
      label: 'Evidence',
      was: 'WARD-A, bed BAY1-01 at version 1',
      now: 'WARD-A, bed BAY1-03 at version 2',
      changed: true,
    });
    expect(rows['Case version']).toEqual({ label: 'Case version', was: '6', now: '9', changed: true });
  });

  it('says a plan of the same version with another digest is another plan', () => {
    const now = replanned();
    now.view = { ...now.view, plan: { ...now.view.plan, version: 1 } };
    expect(byLabel(whatChanged(opened(), now)).Plan).toEqual({
      label: 'Plan',
      was: 'v1',
      now: 'v1, another digest',
      changed: true,
    });
  });

  it('compares no evidence the page has not read, and nothing of a plan that is gone', () => {
    const now = replanned();
    expect(Object.keys(byLabel(whatChanged(opened(), { ...now, snapshot: null })))).not.toContain('Evidence');
    const gone = whatChanged(opened(), { ...now, view: null });
    expect(gone.map((r) => r.label)).toEqual(['Plan', 'Case version']);
    expect(gone[0]).toMatchObject({ now: 'None', changed: true });
  });

  it('marks nothing changed when only the server refused it', () => {
    expect(whatChanged(opened(), opened()).some((r) => r.changed)).toBe(false);
  });
});

describe('why the stopped decision was not recorded', () => {
  it('names the plan that changed, the case that moved under the same plan, or the refusal alone', () => {
    expect(replacedWords(opened(), replanned())).toBe(
      'Your decision on plan v1 was not recorded: the plan changed, and this is plan v2.',
    );
    const moved = opened();
    moved.c = { ...moved.c, version: 7 };
    expect(replacedWords(opened(), moved)).toBe(
      'Your decision on plan v1 was not recorded: the case changed under it, though the plan is the same.',
    );
    expect(replacedWords(opened(), opened())).toBe(
      'Your decision on plan v1 was not recorded: it was refused as stale, though nothing this page reads has changed.',
    );
  });
});

describe('a read older than the review', () => {
  it('is behind, never a change: an older case or plan version', () => {
    const fresh = replanned();
    expect(readBehind(fresh, opened().c, opened().view)).toBe(true);
    expect(readBehind(fresh, fresh.c, opened().view)).toBe(true);
    expect(readBehind(fresh, fresh.c, fresh.view)).toBe(false);
    expect(readBehind(opened(), fresh.c, fresh.view)).toBe(false);
  });
});
