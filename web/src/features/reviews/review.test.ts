import { describe, expect, it } from 'vitest';
import type { ReviewAgent, ReviewDetail } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  describeAgent,
  expiryForApi,
  expiryProblem,
  foundList,
  headerLink,
  hl7Note,
  orderedFindings,
  rankedByAgent,
  subjectOf,
  targetLabel,
} from './review';

const reviews = fixtures.productionReviews.reviews as unknown as Record<string, ReviewDetail>;
const own = reviews['PR-000001'];
const hospital = reviews['PR-000003'];

/** The recorded review as the agent would leave it: every finding ranked, the medium tier reversed. */
function ranked(): ReviewDetail {
  const r = structuredClone(own);
  r.agent = { ...r.agent, state: 'ok', mode: 'replay', error: '', summary: 'Two signatures stand out.' };
  const medium = r.findings.filter((f) => f.severity === 'medium').reverse();
  const low = r.findings.filter((f) => f.severity === 'low');
  [...medium, ...low].forEach((f, i) => {
    f.rank = i + 1;
    f.explanation = `Consistent with ${f.id}.`;
  });
  return r;
}

describe('the order of the findings', () => {
  it('keeps the baseline order unless the agent answered', () => {
    expect(rankedByAgent(own)).toBe(false);
    expect(orderedFindings(own)).toBe(own.findings);
  });

  it("follows the agent's rank when it answered and ranked every finding", () => {
    const r = ranked();
    expect(rankedByAgent(r)).toBe(true);
    const order = orderedFindings(r).map((f) => f.id);
    expect(order[0]).toBe(r.findings.filter((f) => f.severity === 'medium').at(-1)!.id);
    expect(order).toHaveLength(r.findings.length);
    // The server's array is left as it came
    expect(r.findings[0].id).toBe('F1');
  });

  it('keeps the baseline when one finding has no rank, or the ranking was refused', () => {
    const missing = ranked();
    missing.findings[3].rank = null;
    expect(orderedFindings(missing)).toBe(missing.findings);
    const refused = ranked();
    refused.agent.state = 'schema_failed';
    expect(rankedByAgent(refused)).toBe(false);
  });
});

describe('what a finding is about', () => {
  it('names the production or the namespace for a blank item, never a blank', () => {
    const subjects = own.findings.map(subjectOf);
    expect(subjects).not.toContain('');
    expect(subjectOf(own.findings.find((f) => f.code === 'ALERTING_OFF')!)).toBe('the production');
    expect(subjectOf(hospital.findings.find((f) => f.code === 'PURGE_MISSING')!)).toBe('the namespace');
    expect(subjectOf({ code: 'NAMESPACE_UNREADABLE', item: '' })).toBe('the namespace');
    expect(subjectOf({ code: 'FEED_SILENCE_UNWATCHED', item: 'ADT In' })).toBe('ADT In');
  });

  it('splits the production-wide lists into their items and leaves other values whole', () => {
    const alerting = own.findings.find((f) => f.code === 'ALERTING_OFF')!;
    expect(foundList(alerting)).toEqual([
      'ADT In (AlertOnError 0, class default, no AlertGroups)',
      'HL7 Index (AlertOnError 0, class default, no AlertGroups)',
      'ADT to Downstream (AlertOnError 0, class default, no AlertGroups)',
      'Downstream Out (AlertOnError 0, class default, no AlertGroups)',
    ]);
    expect(foundList({ code: 'GIVES_UP_EARLY', found: 'FailureTimeout 5 with RetryInterval 5; x' })).toEqual([
      'FailureTimeout 5 with RetryInterval 5; x',
    ]);
  });

  it('names the HL7 checks with no subject only from the counts the server sent', () => {
    const at = (summary: object) => hl7Note({ ...own, summary: { ...own.summary, ...summary } });
    expect(hl7Note(own)).toBe('');
    expect(at({ hl7Operations: 0, hl7TcpItems: 0 })).toMatch(
      /^No HL7 operation or HL7 TCP item .* reply code and framing/,
    );
    expect(at({ hl7Operations: 0, hl7TcpItems: 1 })).toMatch(/^No HL7 operation .* the reply code checks/);
    expect(at({ hl7Operations: 1, hl7TcpItems: 0 })).toMatch(/^No HL7 TCP item .* the framing check/);
    expect(at({ hl7Operations: 2, hl7TcpItems: 2 })).toBe('');
    expect(hl7Note({ ...own, state: 'failed', summary: { hl7Operations: 0, hl7TcpItems: 0 } })).toBe('');
    expect(hl7Note({ ...own, unreadable: true, summary: { hl7Operations: 0, hl7TcpItems: 0 } })).toBe('');
  });

  it('links a header to the Management Portal of its own namespace', () => {
    expect(headerLink('HOSPITAL', 66)).toBe(
      '/csp/healthshare/hospital/EnsPortal.MessageContents.zen?HeaderId=66',
    );
  });

  it('names a target with its namespace and whose it is', () => {
    expect(fixtures.productionReviews.targets.map(targetLabel)).toEqual([
      "Shutter.Production in SHUTTER, Shutter's own",
      'Hospital.Production in HOSPITAL, watched',
    ]);
  });
});

describe("the agent's state in words", () => {
  const agent = (change: Partial<ReviewAgent>): ReviewAgent => ({ ...own.agent, ...change });

  it('says plainly that no explanation was recorded for this configuration', () => {
    expect(describeAgent(own.agent, 'done').title).toBe('No recorded explanation for this configuration');
  });

  it('says why a refused ranking or a failed run left the baseline order', () => {
    const refused = describeAgent(
      agent({ state: 'schema_failed', error: 'F3 is ranked above a high finding' }),
      'done',
    );
    expect(refused.title).toBe('Explanation not accepted');
    expect(refused.text).toContain('F3 is ranked above a high finding');
    const timedOut = describeAgent(
      agent({ state: 'error', error: 'The agent did not answer within 600 s; the baseline order stands' }),
      'done',
    );
    expect(timedOut.text).toMatch(/^The agent did not answer within 600 s/);
    expect(describeAgent(agent({ state: 'skipped' }), 'done').title).toBe('Not asked');
  });

  it('tells a replayed explanation from a live one, and a pending agent while ranking', () => {
    expect(describeAgent(agent({ state: 'ok', mode: 'replay' }), 'done').title).toBe(
      'Ranked and explained (recorded)',
    );
    expect(describeAgent(agent({ state: 'ok', mode: 'live' }), 'done').title).toBe('Ranked and explained');
    expect(describeAgent(agent({ state: 'pending' }), 'ranking').title).toBe('Ranking');
  });

  it('says the agent was not asked when the sweep failed', () => {
    const failed = describeAgent(agent({ state: 'pending' }), 'failed');
    expect(failed.title).toBe('Not asked');
    expect(failed.text).toMatch(/not asked because the sweep failed/);
  });
});

describe('an expiry', () => {
  it('is empty, or a date after today as the API takes it', () => {
    expect(expiryProblem('', '2026-10-25')).toBeNull();
    expect(expiryProblem('2026-12-31', '2026-10-25')).toBeNull();
    expect(expiryProblem('2026-12-31T18:00Z', '2026-10-25')).toBeNull();
    expect(expiryProblem('31/12/2026', '2026-10-25')).toMatch(/YYYY-MM-DD/);
    expect(expiryProblem('2026-10-25', '2026-10-25')).toBe('An expiry is a date after today');
  });

  it('is sent as the end of its day in UTC, a time as given', () => {
    expect(expiryForApi(' 2026-12-31 ')).toBe('2026-12-31T23:59:59Z');
    expect(expiryForApi('2026-12-31T18:00Z')).toBe('2026-12-31T18:00Z');
    expect(expiryForApi('')).toBe('');
  });
});
