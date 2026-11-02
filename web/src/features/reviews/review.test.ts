import { describe, expect, it } from 'vitest';
import type { ReviewAgent, ReviewDetail, ReviewFinding, ReviewListItem } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  agentLeads,
  describeAgent,
  expiryForApi,
  expiryProblem,
  findingCases,
  findingChip,
  findingSubject,
  findingSummary,
  findingTitle,
  foundList,
  groupBySeverity,
  headerLink,
  hl7Note,
  inFilter,
  latestPerProduction,
  orderedFindings,
  rankedByAgent,
  subjectOf,
  targetLabel,
} from './review';

const reviews = fixtures.productionReviews.reviews as unknown as Record<string, ReviewDetail>;
const own = reviews['PR-000001'];
const hospital = reviews['PR-000003'];
const allFindings: ReviewFinding[] = Object.values(reviews).flatMap((r) => r.findings);
const byId = (r: ReviewDetail, id: string) => r.findings.find((f) => f.id === id)!;

/** The recorded review as the agent would leave it: every finding ranked, the medium tier reversed. */
function ranked(): ReviewDetail {
  const r = structuredClone(own);
  r.agent = { ...r.agent, state: 'ok', mode: 'replay', error: '', summary: 'Two signatures stand out.' };
  const high = r.findings.filter((f) => f.severity === 'high');
  const medium = r.findings.filter((f) => f.severity === 'medium').reverse();
  const low = r.findings.filter((f) => f.severity === 'low');
  [...high, ...medium, ...low].forEach((f, i) => {
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
    // The high finding first, then the medium tier in the agent's order
    expect(order[0]).toBe('F1');
    expect(order[1]).toBe(r.findings.filter((f) => f.severity === 'medium').at(-1)!.id);
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

describe("where the agent's card sits", () => {
  it('leads when the agent ranked, or is ranking now; otherwise it follows the findings', () => {
    expect(agentLeads(own)).toBe(false);
    expect(agentLeads({ state: 'done', agent: { ...own.agent, state: 'ok' } })).toBe(true);
    expect(agentLeads({ state: 'ranking', agent: { ...own.agent, state: 'pending' } })).toBe(true);
    expect(agentLeads({ state: 'sweeping', agent: { ...own.agent, state: 'pending' } })).toBe(false);
    expect(agentLeads({ state: 'done', agent: { ...own.agent, state: 'schema_failed' } })).toBe(false);
    expect(agentLeads({ state: 'done', agent: { ...own.agent, state: 'skipped' } })).toBe(false);
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
      'ADT to Records (AlertOnError 0, class default, no AlertGroups)',
      'Records Out (AlertOnError 0, class default, no AlertGroups)',
    ]);
    expect(foundList({ code: 'GIVES_UP_EARLY', found: 'FailureTimeout 5 with RetryInterval 5; x' })).toEqual([
      'FailureTimeout 5 with RetryInterval 5; x',
    ]);
  });

  it('names the HL7 checks with no subject only from the counts the server sent', () => {
    const at = (summary: object) => hl7Note({ ...own, summary: { ...own.summary, ...summary } });
    // The recording counts none of either
    expect(hl7Note(own)).toMatch(/^No HL7 operation or HL7 TCP item in this production/);
    const { hl7Operations: _ops, hl7TcpItems: _tcp, ...uncounted } = own.summary;
    expect(hl7Note({ ...own, summary: uncounted })).toBe('');
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

  it('says plainly that no explanation was recorded for this configuration, and what the agent does on a live system', () => {
    const view = describeAgent(agent({ state: 'no_record', mode: 'replay' }), 'done');
    expect(view.title).toBe('No recorded explanation for this configuration');
    expect(view.text).toBe(
      'On a live system, an agent ranks these findings and explains each against the cases. This review was recorded without its ranking, so the findings keep the deterministic order.',
    );
    expect(view.text.split(/\s+/).length).toBeLessThanOrEqual(30);
    expect(view.tone).toBe('neutral');
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

describe('the closed row of a finding', () => {
  it('names each code the recordings hold in plain words, and humanises any other', () => {
    expect(findingTitle({ code: 'ALERTING_OFF' })).toBe('No alert on error');
    expect(findingTitle({ code: 'QUEUE_ALERTS_OFF' })).toBe('No alert on a growing queue');
    expect(findingTitle({ code: 'NO_ALERT_CONSUMER' })).toBe('Alerts have nowhere to go');
    expect(findingTitle({ code: 'ERRORS_GROUPED' })).toBe('Repeated errors of one kind');
    expect(findingTitle({ code: 'MESSAGE_ERRORS' })).toBe('Messages that ended in error');
    expect(findingTitle({ code: 'PURGE_MISSING' })).toBe('No message purge task');
    expect(findingTitle({ code: 'FEED_SILENCE_UNWATCHED' })).toBe('A silent feed goes unnoticed');
    expect(findingTitle({ code: 'SUSPENDED_MESSAGES' })).toBe('Suspended messages');
    expect(findingTitle({ code: 'ITEM_DISABLED' })).toBe('An item is switched off');
    expect(findingTitle({ code: 'RETRY_FOREVER' })).toBe('Retry forever');
  });

  it('builds the chip per code from the finding own fields (PR-000001)', () => {
    expect(findingChip(byId(own, 'F1'))).toBe('Second Parser · 1 suspended');
    expect(findingChip(byId(own, 'F2'))).toBe('ERROR <Ens>ErrBPTerminated');
    expect(findingChip(byId(own, 'F3'))).toBe('ADT to Downstream');
    expect(findingChip(byId(own, 'F10'))).toBe('AlertOnError');
    expect(findingChip(byId(own, 'F11'))).toBe('no Ens.Alert item');
    expect(findingChip(byId(own, 'F12'))).toBe('ADT In · InactivityTimeout = 0');
    // A queue finding over two items names the setting alone; over one, the item too
    expect(findingChip(byId(own, 'F13'))).toBe('QueueCountAlert');
    expect(findingChip(byId(hospital, 'F7'))).toBe('QueueCountAlert · Downstream Out');
  });

  it('builds the chip of the purge finding, and never cuts a long value', () => {
    // The purge finding has no setting and a long value: no chip, the open finding shows it in full
    expect(findingChip(byId(hospital, 'F2'))).toBeNull();
    // ALERTING_OFF lists six items: the row shows the setting, never half of the list
    const alerting = byId(own, 'F10');
    expect(alerting.found.length).toBeGreaterThan(100);
    expect(findingChip(alerting)).toBe('AlertOnError');
    // A code without a template takes item, setting and a short value, each only when present
    const other = {
      ...alerting,
      code: 'GIVES_UP_EARLY',
      item: 'ADT In',
      setting: 'FailureTimeout',
      found: '5',
    };
    expect(findingChip(other)).toBe('ADT In · FailureTimeout = 5');
    expect(findingChip({ ...other, item: '', found: 'a value of more than twenty-four characters' })).toBe(
      'FailureTimeout',
    );
    expect(findingChip({ ...other, item: '', setting: '', found: '' })).toBeNull();
  });

  it('builds a summary of at most 15 words for each of PR-000001 and PR-000003, with real plurals', () => {
    expect(findingSummary(byId(own, 'F2'))).toBe(
      '82 errors with one signature, logged by ADT to Downstream.',
    );
    expect(findingSummary(byId(own, 'F3'))).toBe('82 messages ended in error, from ADT In.');
    expect(findingSummary(byId(own, 'F6'))).toBe('1 error with one signature, logged by Second Parser.');
    expect(findingSummary(byId(own, 'F10'))).toBe(
      'Failures reach the event log and wait for someone to read it.',
    );
    expect(findingSummary(byId(own, 'F11'))).toBe('An alert raised by any item reaches nobody.');
    expect(findingSummary(byId(own, 'F12'))).toBe('A feed that falls silent is never noticed.');
    expect(findingSummary(byId(own, 'F13'))).toBe('A growing queue at 2 items raises no alert.');
    expect(findingSummary(byId(hospital, 'F2'))).toBe('Old messages are never purged.');
    expect(findingSummary(byId(hospital, 'F3'))).toBe(
      '1 error with one signature, logged by PAS to Downstream.',
    );
    expect(findingSummary(byId(hospital, 'F4'))).toBe('1 message ended in error, from PAS In.');
    expect(findingSummary(byId(hospital, 'F7'))).toBe('A growing queue at Downstream Out raises no alert.');
    // An error group the production logged itself, with no item
    expect(findingSummary({ ...byId(own, 'F6'), item: '' })).toBe(
      '1 error with one signature, logged by the production itself.',
    );
    expect(findingSummary(byId(own, 'F1'))).toBe(
      '1 message to Second Parser is suspended, waiting for a person.',
    );
    expect(findingSummary(byId(hospital, 'F1'))).toBe(
      'Live PAS is switched off: its messages queue up or go nowhere.',
    );
  });

  it('never lets the server text that reads badly into a row: no (s), no "by .", no double space', () => {
    expect(allFindings.length).toBeGreaterThanOrEqual(22);
    for (const f of allFindings) {
      for (const text of [
        findingSummary(f),
        findingTitle(f),
        findingChip(f) ?? '',
        findingSubject(f) ?? '',
      ]) {
        expect(text).not.toMatch(/\(s\)|by \.|on {2}| {2}/);
      }
      expect(findingSummary(f).split(/\s+/).length).toBeLessThanOrEqual(15);
    }
    // The server's sentence with a count in the singular is what the row avoids
    expect(byId(own, 'F1').why).toContain('1 message(s)');
    expect(findingSummary(byId(own, 'F1'))).not.toContain('(s)');
  });

  it('takes the first clean sentence of the server text for a code without a template, else the plain title', () => {
    const base = byId(own, 'F13');
    const clean = {
      ...base,
      code: 'GIVES_UP_EARLY',
      why: 'The item is switched off. A message sent to it waits in the queue.',
    };
    expect(findingSummary(clean)).toBe('The item is switched off.');
    expect(findingSummary({ ...clean, why: 'The item has 2 setting(s) off. More.' })).toBe('Gives up early');
    expect(findingSummary({ ...clean, why: 'Logged by . It stays.' })).toBe('Gives up early');
    expect(
      findingSummary({
        ...clean,
        why: 'This sentence has far too many words for a closed row to carry in full, so it is not used. Second.',
      }),
    ).toBe('Gives up early');
  });

  it('puts the subject beside the chip only when the chip or the summary does not name it already', () => {
    expect(findingSubject(byId(own, 'F1'))).toBeNull();
    expect(findingSubject(byId(own, 'F10'))).toBe('ADT In, HL7 Index, +4');
    // A finding about the whole production with a chip needs no "the production" beside it
    expect(findingSubject(byId(own, 'F11'))).toBeNull();
    expect(findingSubject(byId(own, 'F13'))).toBeNull();
    expect(findingSubject(byId(own, 'F3'))).toBeNull();
    expect(findingSubject(byId(own, 'F12'))).toBeNull();
    expect(findingSubject(byId(hospital, 'F2'))).toBe('the namespace');
    expect(
      findingSubject({ ...byId(own, 'F10'), found: 'ADT In (AlertOnError 0); HL7 Index (AlertOnError 0)' }),
    ).toBe('ADT In, HL7 Index');
  });

  it('counts the cases in the right number, and says nothing for a finding with none', () => {
    expect(findingCases(byId(hospital, 'F6'))).toBe('1 case, 1 unique');
    expect(findingCases({ cases: { count: 54, unique: 30, latest: [] } })).toBe('54 cases, 30 unique');
    expect(findingCases(byId(own, 'F2'))).toBeNull();
  });
});

describe('grouping and filtering the findings', () => {
  it('groups by severity, most severe first, keeping the order within each tier', () => {
    expect(groupBySeverity(own.findings).map((g) => [g.severity, g.findings.length])).toEqual([
      ['high', 1],
      ['medium', 10],
      ['low', 2],
    ]);
    expect(groupBySeverity(hospital.findings).map((g) => g.severity)).toEqual(['high', 'medium', 'low']);
    expect(groupBySeverity(hospital.findings)[1].findings.map((f) => f.id)).toEqual(['F3', 'F4', 'F5']);
    expect(groupBySeverity([])).toEqual([]);
  });

  it('filters by tier, new and marked (any status but new)', () => {
    // The recording marks nothing; with its first finding marked intended
    expect(own.findings.filter((f) => inFilter(f, 'marked'))).toEqual([]);
    const findings = structuredClone(own.findings);
    findings[0].status = 'intended';
    expect(findings.filter((f) => inFilter(f, 'marked')).map((f) => f.id)).toEqual(['F1']);
    expect(findings.filter((f) => inFilter(f, 'new'))).toHaveLength(12);
    expect(findings.filter((f) => inFilter(f, 'low')).map((f) => f.id)).toEqual(['F12', 'F13']);
    expect(findings.filter((f) => inFilter(f, 'all'))).toHaveLength(13);
    expect(findings.filter((f) => inFilter(f, 'high')).map((f) => f.id)).toEqual(['F1']);
  });
});

describe('the latest review of each production', () => {
  const list = fixtures.productionReviews.list as unknown as ReviewListItem[];

  it('is the newest of each, newest first', () => {
    expect(latestPerProduction(list).map((r) => r.reviewId)).toEqual(['PR-000004', 'PR-000003']);
  });

  it('takes the higher id when two start together, and copes with no reviews', () => {
    const twin = { ...list[0], reviewId: 'PR-000009' };
    expect(latestPerProduction([list[0], twin]).map((r) => r.reviewId)).toEqual(['PR-000009']);
    expect(latestPerProduction([])).toEqual([]);
  });
});
