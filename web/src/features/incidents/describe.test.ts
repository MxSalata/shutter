import { describe, expect, it } from 'vitest';
import type { Chain, ChainItem, IncidentDetail, IncidentEvent } from '@/api/types';
import { caseOutcome } from '@/lib/status';
import recorded from './test-incident.json';
import {
  allVerified,
  approvalSentence,
  chainLine,
  chainTally,
  decidedBy,
  describeChain,
  describePolicy,
  heroSentence,
  incidentLead,
  itemOutcome,
  openToClosed,
  planSentence,
  shortEvent,
  statesFromCounts,
  tidy,
  timelineLines,
  versions,
} from './describe';

const closed = recorded.detail as unknown as IncidentDetail;
const progress = (chains: number, cases: number, byState: Record<string, number>) => ({
  chains,
  cases,
  byKind: {},
  byState,
});
const base = {
  state: 'closed' as const,
  openedAt: '2026-10-20T17:36:24Z',
  closedAt: '2026-10-20T17:38:06Z',
};

describe('heroSentence', () => {
  it('leads with what was measured when every chain was verified: failures, patients, all verified, how fast', () => {
    expect(heroSentence({ ...base, progress: progress(6, 8, { resolved: 6 }) })).toBe(
      '8 failed messages for 6 patient encounters, all closed and verified at the receiver, in 1 min 42 s.',
    );
  });

  it("is within the hero band's 24 words", () => {
    const words = heroSentence({ ...base, progress: progress(6, 8, { resolved: 6 }) }).split(/\s+/);
    expect(words.length).toBeLessThanOrEqual(24);
  });

  it('says "closed and verified" without "all" for a single chain, and "1 failed message" in the singular', () => {
    expect(heroSentence({ ...base, progress: progress(1, 1, { resolved: 1 }) })).toBe(
      '1 failed message for 1 patient encounter, closed and verified at the receiver, in 1 min 42 s.',
    );
  });

  it('leaves the time out when the incident carries no closing time', () => {
    expect(heroSentence({ ...base, closedAt: undefined, progress: progress(2, 3, { resolved: 2 }) })).toBe(
      '3 failed messages for 2 patient encounters, all closed and verified at the receiver.',
    );
  });

  it('counts the chains by how they ended when one stopped or went to a person', () => {
    expect(
      heroSentence({ ...base, progress: progress(6, 8, { resolved: 4, stopped: 1, escalated: 1 }) }),
    ).toBe('8 failed messages for 6 patient encounters: 4 chains verified, 1 stopped, 1 with a person.');
  });

  it('starts the count with whatever came first when none was verified', () => {
    expect(heroSentence({ ...base, progress: progress(2, 2, { stopped: 1, rejected: 1 }) })).toBe(
      '2 failed messages for 2 patient encounters: 1 chain stopped, 1 rejected.',
    );
  });

  it('says "so far, taking cases" while the incident is open', () => {
    expect(
      heroSentence({
        state: 'open',
        openedAt: base.openedAt,
        progress: progress(0, 5, {}),
      }),
    ).toBe('5 failed messages so far, taking cases.');
    expect(
      heroSentence({
        state: 'open',
        openedAt: base.openedAt,
        progress: progress(4, 5, {}),
      }),
    ).toBe('5 failed messages for 4 patient encounters so far, taking cases.');
  });

  it('reads the chains still to be released while the incident releases them', () => {
    expect(
      heroSentence({
        state: 'releasing',
        openedAt: base.openedAt,
        progress: progress(6, 8, { resolved: 3, releasing: 1, approved: 1, awaiting_approval: 1 }),
      }),
    ).toBe(
      '8 failed messages for 6 patient encounters: 3 chains verified, 1 waiting for approval, 2 being released.',
    );
  });

  it('never prints a plural as "(s)"', () => {
    for (const p of [progress(1, 1, { resolved: 1 }), progress(3, 4, { resolved: 2, stopped: 1 })])
      expect(heroSentence({ ...base, progress: p })).not.toMatch(/\(s\)/);
  });
});

describe('openToClosed and allVerified', () => {
  it('measures from opening to closing', () => {
    expect(openToClosed(base)).toBe(102_000);
    expect(openToClosed({ openedAt: base.openedAt })).toBeUndefined();
  });

  it('needs the incident closed and every chain resolved', () => {
    expect(allVerified({ state: 'closed', progress: progress(2, 2, { resolved: 2 }) })).toBe(true);
    expect(allVerified({ state: 'closed', progress: progress(2, 2, { resolved: 1, stopped: 1 }) })).toBe(
      false,
    );
    expect(allVerified({ state: 'releasing', progress: progress(2, 2, { resolved: 2 }) })).toBe(false);
  });
});

describe('incidentLead', () => {
  it('builds the page lead from the cases it holds and its receiver', () => {
    const lead = incidentLead({ receiver: 'Downstream Out', progress: progress(6, 8, {}) });
    expect(lead).toBe('8 failed deliveries to Downstream Out, grouped and released in order, one at a time.');
    expect(lead.split(/\s+/)).toHaveLength(15);
    expect(incidentLead({ receiver: 'Downstream Out', progress: progress(1, 1, {}) })).toContain(
      '1 failed delivery to',
    );
  });
});

describe('chainTally', () => {
  it('puts the noun on the first count only', () => {
    expect(chainTally({ resolved: 4, stopped: 1, escalated: 1 })).toBe(
      '4 chains verified, 1 stopped, 1 with a person',
    );
    expect(chainTally({ resolved: 1 })).toBe('1 chain verified');
    expect(chainTally({})).toBe('');
  });
});

describe('chainLine', () => {
  const chain = (decides: string, policy: string) => ({ decides, policy }) as Chain;
  it("says who decides a chain in the newcomer's words", () => {
    expect(chainLine(chain('policy', 'automatic'))).toBe('Site policy, automatic');
    expect(chainLine(chain('policy', 'approval'))).toBe('Site policy, one approval');
    expect(chainLine(chain('policy', 'per_chain'))).toBe('Site policy, its own approval');
    expect(chainLine(chain('board', 'path'))).toBe('The board of agents decides');
    expect(chainLine(chain('person', 'path'))).toBe('A person decides');
  });
});

describe('decidedBy', () => {
  it('counts who decided the chains and the approvals the release took', () => {
    const { deciders, approvals } = decidedBy(closed.chains);
    expect(deciders.map((d) => [d.label, d.seqs])).toEqual([
      ['Site policy', [1, 2, 4, 5, 6]],
      ['The board', [3]],
    ]);
    expect(approvals).toBe(1);
  });

  it('counts a chain released under its own approval as an approval of its own', () => {
    const chains = [
      { seq: 1, decides: 'policy', policy: 'approval' },
      { seq: 2, decides: 'policy', policy: 'per_chain' },
      { seq: 3, decides: 'policy', policy: 'per_chain' },
      { seq: 4, decides: 'policy', policy: 'automatic' },
    ] as Chain[];
    expect(decidedBy(chains).approvals).toBe(3);
    expect(decidedBy([{ seq: 1, decides: 'policy', policy: 'automatic' }] as Chain[]).approvals).toBe(0);
  });
});

describe('an operation', () => {
  const item = (over: Partial<ChainItem>): ChainItem =>
    ({
      state: 'resolved',
      caseState: 'resolved',
      entry: 'E2',
      outcome: 'resend',
      expectedVersion: null,
      verifiedVersion: 2,
      ...over,
    }) as ChainItem;

  it('reads as the case outcome: delivered when it was resent, nothing to send when it was not', () => {
    expect(caseOutcome(itemOutcome(item({}))!).short).toBe('Delivered, verified');
    expect(caseOutcome(itemOutcome(item({ outcome: 'resend_chain' }))!).short).toBe('Delivered, verified');
    expect(caseOutcome(itemOutcome(item({ outcome: 'none' }))!).short).toBe('Nothing to send, verified');
    // The outcome it was released under wins over the one it was matched under
    expect(caseOutcome(itemOutcome(item({ outcome: 'resend', releaseOutcome: 'none' }))!).short).toBe(
      'Nothing to send, verified',
    );
  });

  it('reads as the case would when a check stopped it or it went to a person', () => {
    expect(caseOutcome(itemOutcome(item({ state: 'blocked', caseState: 'blocked' }))!).short).toBe('Blocked');
    expect(caseOutcome(itemOutcome(item({ state: 'escalated', caseState: 'escalated' }))!).short).toBe(
      'Escalated',
    );
  });

  it('has no case outcome before it is released or when it never was: its own state says so', () => {
    expect(itemOutcome(item({ state: 'pending', caseState: 'grouped' }))).toBeNull();
    expect(itemOutcome(item({ state: 'stopped', caseState: 'grouped' }))).toBeNull();
  });

  it('states its versions, and leaves the arrow open until the verification read one', () => {
    expect(versions(item({ expectedVersion: 1, verifiedVersion: 2 }))).toBe('v1 → v2');
    expect(versions(item({ expectedVersion: null, verifiedVersion: 2 }))).toBe('fresh evidence → v2');
    expect(versions(item({ expectedVersion: 2, verifiedVersion: null, state: 'pending' }))).toBe('v2 → …');
    expect(versions(item({ expectedVersion: 2, verifiedVersion: null, state: 'blocked' }))).toBe('v2');
  });
});

describe('tidy', () => {
  it('writes the server\'s "(s)" as a plural in the right number', () => {
    expect(tidy('6 chain(s) formed')).toBe('6 chains formed');
    expect(tidy('1 item(s) resolved in order')).toBe('1 item resolved in order');
    expect(tidy('1 approval task(s) raised')).toBe('1 approval task raised');
    expect(tidy('Closed: 6 chain(s): 6 resolved')).toBe('Closed: 6 chains: 6 resolved');
  });
});

describe('the timeline', () => {
  const event = (
    kind: string,
    text: string,
    at = '2026-10-18T11:04:27Z',
    actor = 'system',
  ): IncidentEvent => ({
    kind,
    text,
    at,
    actor,
  });

  it('writes the opening line as its fact', () => {
    expect(shortEvent('Incident opened for Downstream Out: 5 failures within 10 minutes (mode policy)')).toBe(
      'Opened: 5 failures within 10 minutes',
    );
  });

  it('cuts a long line at its first clause and leaves out the digest and the task number', () => {
    expect(shortEvent('6 chain(s) formed; plan digest sha256:f42f69be8a57. chain 1 ENC-1101: single')).toBe(
      '6 chains formed',
    );
    expect(
      shortEvent(
        'Approved by approver (task 148, plan digest sha256:f42f69be8a57), the policy chains under one approval',
      ),
    ).toBe('Approved by approver, the policy chains under one approval');
  });

  it('collapses consecutive joined cases into one line, and runs of one kind into a count', () => {
    const lines = timelineLines(recorded.events as IncidentEvent[]);
    expect(lines.map((l) => l.label)).toEqual([
      'Opened: 5 failures within 10 minutes',
      '5 cases joined',
      'Intake open: the chains form after 60 s with no new failure to Downstream Out',
      '3 cases joined',
      '2 notes',
      '6 chains formed',
      '2 notes',
      '2 status changes',
      '7 release steps',
      'Approved by approver, the policy chains under one approval',
      '20 release steps',
      'Closed: 6 chains: 6 resolved, 0 stopped, 0 escalated, 0 rejected',
    ]);
  });

  it('opens a line only when the events say more than its words', () => {
    const lines = timelineLines(recorded.events as IncidentEvent[]);
    const opens = Object.fromEntries(lines.map((l) => [l.label, l.opens]));
    expect(opens['Opened: 5 failures within 10 minutes']).toBe(false);
    expect(opens['Intake open: the chains form after 60 s with no new failure to Downstream Out']).toBe(
      false,
    );
    expect(opens['Closed: 6 chains: 6 resolved, 0 stopped, 0 escalated, 0 rejected']).toBe(false);
    expect(opens['5 cases joined']).toBe(true);
    expect(opens['6 chains formed']).toBe(true);
    expect(opens['Approved by approver, the policy chains under one approval']).toBe(true);
  });

  it('keeps the events of a line as the server wrote them, and names the person behind an approval', () => {
    const lines = timelineLines([
      event('approval', 'Approved by approver (task 1)', '2026-10-18T11:10:29Z', 'approver'),
    ]);
    expect(lines).toHaveLength(1);
    expect(lines[0].actor).toBe('approver');
    expect(lines[0].events[0].text).toBe('Approved by approver (task 1)');
    expect(timelineLines([event('note', 'Intake open: x')])[0].actor).toBe('');
  });

  it('says "1 case joined" in the singular and gives a lone joined case its own line', () => {
    const lines = timelineLines([
      event('note', 'Case C-000001 joined: transfer for ENC-1 (delivery_failed)'),
    ]);
    expect(lines[0].label).toBe('Case C-000001 joined: transfer for ENC-1');
  });
});

describe('the long forms, for a tooltip and the engineer', () => {
  it('says how the policy chains were authorised, as one sentence', () => {
    expect(describePolicy('approval')).toBe(
      "The policy chains are released under one approval of the incident's plan",
    );
    expect(describePolicy('automatic')).toMatch(/released automatically/);
    expect(describePolicy(undefined)).toBe('');
  });

  it("names a chain's kind, who decides it and how it is released", () => {
    const ordered = closed.chains.find((c) => c.seq === 2)!;
    expect(describeChain(ordered)).toBe(
      "Ordered, decided by site policy, released under the incident's approval",
    );
    expect(describeChain(closed.chains.find((c) => c.seq === 3)!)).toBe('Interleaved, decided by the board');
  });
});

describe('the approval and the plan in a sentence', () => {
  const ordered = closed.chains.find((c) => c.seq === 2)!;
  const approved = closed.approvals[0];

  it('says what the one approval released, in the usual 9 words', () => {
    const sentence = approvalSentence([ordered], approved);
    expect(sentence).toBe('One approval released the ordered chain: C-000004 then C-000009.');
    expect(sentence.split(/\s+/)).toHaveLength(9);
  });

  it('says what it releases while it waits, and what a rejection stopped', () => {
    expect(approvalSentence([ordered], undefined)).toBe(
      'One approval releases the ordered chain: C-000004 then C-000009.',
    );
    expect(approvalSentence([ordered], { ...approved, decision: 'rejected' })).toBe(
      'One rejection stopped the ordered chain: C-000004 then C-000009. Nothing was sent.',
    );
  });

  it('counts the chains when it covers more than one', () => {
    const second = { ...ordered, seq: 7, items: [{ ...ordered.items[0], caseId: 'C-000099' }] };
    expect(approvalSentence([ordered, second], approved)).toBe(
      'One approval released 2 chains: C-000004 then C-000009; C-000099.',
    );
  });

  it('says what the plan covers, from the chains that need the approval', () => {
    expect(planSentence(closed.chains)).toBe('One plan, approved once, covers the ordered chain.');
    expect(planSentence([ordered, { ...ordered, seq: 7 }])).toBe('One plan, approved once, covers 2 chains.');
    expect(planSentence(closed.chains.filter((c) => c.policy === 'automatic'))).toBe(
      'One plan covers every chain; none of them needs an approval.',
    );
  });
});

describe('statesFromCounts', () => {
  it('gives one state per chain, the verified first and the ones that need a person last', () => {
    expect(statesFromCounts({ stopped: 1, resolved: 3, escalated: 1 })).toEqual([
      'resolved',
      'resolved',
      'resolved',
      'escalated',
      'stopped',
    ]);
    expect(statesFromCounts(undefined)).toEqual([]);
  });
});
