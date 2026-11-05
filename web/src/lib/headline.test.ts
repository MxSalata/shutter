import { describe, expect, it } from 'vitest';
import fixtures from '@/mocks/fixtures.json';
import { clampHeadline } from './headline';

const recorded = (id: string) =>
  (fixtures.cases as unknown as Record<string, { summary: { headline: string } }>)[id].summary.headline;
const opening = 'Escalated to a person. ';

describe('clampHeadline', () => {
  it('ends a headline cut mid-word at its last whole word, with an ellipsis', () => {
    const summary = `${'word '.repeat(39)}abcde`;
    expect(summary).toHaveLength(200);
    expect(clampHeadline(opening + summary)).toBe(`${opening}${'word '.repeat(38)}word…`);
  });

  it('shows a headline the server cut at a word as it is', () => {
    expect(recorded('C-000008').endsWith('That state was set by…')).toBe(true);
    for (const id of ['C-000002', 'C-000008']) expect(clampHeadline(recorded(id))).toBe(recorded(id));
  });

  it('leaves a headline whose summary was not cut as it is', () => {
    for (const id of ['C-000012', 'C-000031']) expect(clampHeadline(recorded(id))).toBe(recorded(id));
    expect(clampHeadline('Blocked at dispatch: the receiver could not be read (timeout)')).toBe(
      'Blocked at dispatch: the receiver could not be read (timeout)',
    );
  });

  it('keeps a cut that falls at the end of a sentence', () => {
    const summary = `${'word '.repeat(39)}done.`;
    expect(summary).toHaveLength(200);
    expect(clampHeadline(opening + summary)).toBe(opening + summary);
  });

  it('drops the punctuation a cut leaves hanging', () => {
    const summary = `${'word '.repeat(38)}one, twoth`;
    expect(summary).toHaveLength(200);
    expect(clampHeadline(opening + summary)).toBe(`${opening}${'word '.repeat(38)}one…`);
  });

  it('puts the ellipsis in place of a full stop the cut leaves', () => {
    const summary = `${'word '.repeat(38)}wordy. Rab`;
    expect(summary).toHaveLength(200);
    expect(clampHeadline(opening + summary)).toBe(`${opening}${'word '.repeat(38)}wordy…`);
  });

  it('drops a full stop an earlier server cut left before its ellipsis', () => {
    expect(clampHeadline(`${opening}The receiver is at version 2, epoch 30.…`)).toBe(
      `${opening}The receiver is at version 2, epoch 30…`,
    );
  });

  it("ends the team's reason for a case handled by hand, which the server also cuts at 200", () => {
    const reason = `${'fixed '.repeat(32)}by the h`;
    expect(reason).toHaveLength(200);
    expect(clampHeadline(`Handled by the team. ${reason}`)).toBe(
      `Handled by the team. ${'fixed '.repeat(32)}by the…`,
    );
  });

  it('reads through a rejection', () => {
    const cut = recorded('C-000008');
    expect(clampHeadline(`Rejected by approver: ${cut}`)).toBe(`Rejected by approver: ${clampHeadline(cut)}`);
  });

  it("reads the gate's headline as the checks that failed, without doubling Blocked or the raw codes", () => {
    expect(
      clampHeadline(
        'Blocked by the gate: Blocked: ordering SUPERSEDED_BY_LATER_EVENT (policy 2026-10-20.1, stage proposal)',
      ),
    ).toBe('Blocked by the gate: the ordering check failed.');
    expect(
      clampHeadline(
        'Blocked by the gate: Blocked: ordering SUPERSEDED_BY_LATER_EVENT, state_transition INVALID_TRANSITION (policy 2026-10-20.1, stage proposal)',
      ),
    ).toBe('Blocked by the gate: the ordering and state transition checks failed.');
  });

  it("says what stopped a message it couldn't read, never that a sound message failed a check", () => {
    const stage = '(policy 2026-11-01.1, stage proposal)';
    expect(clampHeadline(`Blocked by the gate: Blocked: conformance PARSE_FAILED ${stage}`)).toBe(
      "Blocked by the gate: the message couldn't be read or mapped to an operation.",
    );
    expect(clampHeadline(`Blocked by the gate: Blocked: conformance SCHEMA_UNKNOWN ${stage}`)).toBe(
      "Blocked by the gate: the message's schema is not loaded here.",
    );
    // Another conformance reason, and another check, keep the check's name
    expect(clampHeadline(`Blocked by the gate: Blocked: conformance UNMAPPABLE ${stage}`)).toBe(
      'Blocked by the gate: the conformance check failed.',
    );
    expect(clampHeadline(recorded('C-000064'))).toBe(
      "Blocked by the gate: the message couldn't be read or mapped to an operation.",
    );
  });

  it('never leaves a recorded headline ending mid-word', () => {
    for (const c of Object.values(fixtures.cases)) {
      if (c.summary.headline.startsWith('Blocked by the gate: ')) continue;
      const shown = clampHeadline(c.summary.headline);
      expect(shown === c.summary.headline || /[^\s.,;:(-]…$/.test(shown)).toBe(true);
    }
  });
});
