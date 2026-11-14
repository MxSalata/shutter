import { describe, expect, it } from 'vitest';
import type { AgentRun, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  planReason,
  proposalLabel,
  proposerOf,
  reasonLabel,
  reasonSource,
  specialistsLine,
} from './contribution';

type Id = keyof typeof fixtures.cases;

const planOf = (id: Id) => fixtures.cases[id].plan as unknown as PlanView;
const runsOf = (id: Id) => fixtures.cases[id].runs as unknown as AgentRun[];
const snapshotOf = (id: Id) => fixtures.cases[id].snapshot as unknown as Snapshot;

/** A plan with another origin, the rest as recorded. */
const madeBy = (id: Id, createdBy: string): PlanView => {
  const view = structuredClone(planOf(id));
  view.plan!.createdBy = createdBy;
  return view;
};

describe('who proposed the plan', () => {
  it("names the coordinator agent on the board's S2, S3 and S8, from the run the plan itself names", () => {
    for (const id of ['C-000002', 'C-000003', 'C-000008'] as Id[]) {
      const proposer = proposerOf(planOf(id), runsOf(id));
      expect(proposer.kind).toBe('agent');
      if (proposer.kind !== 'agent') return;
      expect(proposer.role).toBe('coordinator');
      expect(`run:${proposer.run.id}`).toBe(planOf(id).plan!.createdBy);
      expect(proposalLabel(proposer)).toBe("Coordinator agent's proposal");
      expect(reasonSource(proposer)).toBe("The coordinator agent's reason, as its run recorded it");
    }
  });

  it('names the single investigator when its run made the plan', () => {
    const run = { ...runsOf('C-000008').find((r) => r.role === 'coordinator')!, role: 'generalist' };
    const proposer = proposerOf(planOf('C-000008'), [run]);
    expect(proposalLabel(proposer)).toBe("One agent's proposal");
    expect(reasonSource(proposer)).toBe("The agent's reason, as its run recorded it");
  });

  it('claims no agent for a plan the rules or the site policy wrote', () => {
    const rules = proposerOf(planOf('C-000021'), runsOf('C-000021'));
    expect(rules).toEqual({ kind: 'rules' });
    expect(proposalLabel(rules)).toBe("The rules' proposal, no agent");
    const policy = proposerOf(planOf('C-000028'), runsOf('C-000028'));
    expect(policy).toEqual({ kind: 'policy', entry: 'E2' });
    expect(proposalLabel(policy)).toBe("Site policy's proposal, no agent");
    expect(reasonSource(policy)).toBe("The site's policy gives this reason; no agent ran");
  });

  it('claims no agent when the board ran and the rules path made the plan', () => {
    // A board nobody answered on: its runs are on the case, and the plan is the rules' plain resend
    const failed = runsOf('C-000008').map((r) => ({ ...r, status: 'error', result: null }));
    const proposer = proposerOf(madeBy('C-000008', 'rules'), failed as AgentRun[]);
    expect(proposer).toEqual({ kind: 'rules' });
    expect(specialistsLine(proposer, failed as AgentRun[])).toBe('');
  });

  it('claims no agent while the runs are not read, for a run that is not on the case, and for one that failed', () => {
    expect(proposerOf(planOf('C-000008'), undefined)).toEqual({ kind: 'unknown' });
    expect(proposerOf(planOf('C-000008'), runsOf('C-000002'))).toEqual({ kind: 'unknown' });
    const failed = runsOf('C-000008').map((r) => ({ ...r, status: 'error' }));
    expect(proposerOf(planOf('C-000008'), failed)).toEqual({ kind: 'unknown' });
    expect(proposalLabel({ kind: 'unknown' })).toBe('Proposal');
    expect(proposerOf(null, runsOf('C-000008'))).toEqual({ kind: 'unknown' });
  });

  it("leaves a question's runs out: only the investigation's can have made the plan", () => {
    const asked = runsOf('C-000008').map((r) => ({ ...r, questionId: 'Q-000001' }));
    expect(proposerOf(planOf('C-000008'), asked)).toEqual({ kind: 'unknown' });
  });

  it('names the board of the case a follower took its plan from, and a withheld plan as nobody', () => {
    const lead = proposerOf(madeBy('C-000008', 'lead:C-000007'), []);
    expect(lead).toEqual({ kind: 'lead', leader: 'C-000007' });
    expect(proposalLabel(lead)).toBe("Proposal from case C-000007's board");
    const withheld = proposerOf(madeBy('C-000008', 'withheld'), []);
    expect(withheld).toEqual({ kind: 'withheld' });
    expect(proposalLabel(withheld)).toBe('Proposal');
  });
});

describe("the plan's recorded reason", () => {
  it('gives the reason word for word, the entry with its title from the evidence, and what the plan cites', () => {
    const s8 = planReason(planOf('C-000008'), snapshotOf('C-000008'))!;
    expect(s8.why).toBe(planOf('C-000008').plan!.why);
    expect(s8.entry).toEqual({ code: 'E7', title: 'Two sources at the same time' });
    expect(s8.refs).toEqual([
      'message',
      'validation',
      'error',
      'operation',
      'route',
      'ward_state',
      'receipt',
      'timeline',
    ]);
    expect(s8.entries).toEqual(['E7']);
    expect(reasonLabel(s8)).toBe('Why: Two sources at the same time');
    expect(reasonLabel(planReason(planOf('C-000002'), snapshotOf('C-000002'))!)).toBe(
      'Why: Not delivered, still current',
    );
    expect(reasonLabel(planReason(planOf('C-000003'), snapshotOf('C-000003'))!)).toBe(
      'Why: Committed after all',
    );
  });

  it('names no title when the evidence is not read, and makes nothing up', () => {
    const reason = planReason(planOf('C-000008'), undefined)!;
    expect(reason.entry).toEqual({ code: 'E7', title: '' });
    expect(reasonLabel(reason)).toBe('Why, as recorded');
  });

  it("has nothing for the rules' plain resend, which records no reason, and for no plan", () => {
    expect(planReason(planOf('C-000021'), snapshotOf('C-000021'))).toBeNull();
    expect(planReason(null, snapshotOf('C-000008'))).toBeNull();
    expect(planReason(undefined, undefined)).toBeNull();
  });

  it("keeps a policy plan's reason as the policy's", () => {
    const reason = planReason(planOf('C-000028'), snapshotOf('C-000028'))!;
    expect(reason.why).toBe(planOf('C-000028').plan!.why);
    expect(reason.entry?.code).toBe('E2');
    expect(reason.entries).toEqual(['E2']);
  });
});

describe('how the specialists stood to the plan', () => {
  const line = (id: Id) => specialistsLine(proposerOf(planOf(id), runsOf(id)), runsOf(id));

  it('says who proposed the same and whose dissent the plan keeps', () => {
    expect(line('C-000002')).toBe('Conformance, Encounter Integrity and Impact Analysis proposed the same.');
    expect(line('C-000008')).toBe(
      'Encounter Integrity and Impact Analysis proposed the same; Conformance proposed resend, which the plan keeps as dissent.',
    );
    expect(line('C-000003')).toBe(
      'Encounter Integrity and Impact Analysis proposed the same; Conformance proposed resend, which the plan keeps as dissent.',
    );
  });

  it('says which specialist gave no answer, and nothing for a plan no coordinator made', () => {
    const runs = runsOf('C-000002').map((r) =>
      r.memberCode === 'impact' ? { ...r, status: 'error', result: null, finding: null } : r,
    ) as AgentRun[];
    expect(specialistsLine(proposerOf(planOf('C-000002'), runs), runs)).toBe(
      'Conformance and Encounter Integrity proposed the same; Impact Analysis gave no answer.',
    );
    expect(specialistsLine({ kind: 'rules' }, runsOf('C-000002'))).toBe('');
    expect(specialistsLine({ kind: 'unknown' }, runsOf('C-000002'))).toBe('');
  });
});
