import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { ReceiverCheck } from '@/api/types';
import fixtures from './fixtures.json';
import { receiverCheckFor, type RecordedCase } from './receiverCheck';
import words from './receiver-check-words.json';

const recorded = (id: string) => (fixtures.cases as unknown as Record<string, RecordedCase>)[id]!;
const card = (id: string) =>
  receiverCheckFor(recorded(id), fixtures.siteProfile.profile as never) as ReceiverCheck;

describe("the demo's receiver check", () => {
  it('uses the words the server uses', () => {
    const source = readFileSync(resolve(__dirname, '../../../src/Shutter/Util/ReceiverCheck.cls'), 'utf8');
    const block =
      /XData Words \[ MimeType = application\/json \]\n\{\n([\s\S]*?)\n\}\n\n\/\/\/ The card's versioned/.exec(
        source,
      );
    expect(block).not.toBeNull();
    expect(JSON.parse(block![1]!)).toEqual(words);
  });

  it.each([
    ['C-000008', 'later_movement'], // S8: another source moved the patient at the same time
    ['C-000011', 'identity_or_time'], // S13: a doubtful event time
    ['C-000010', 'manual_compare'], // S10: the receiver can't take a conditional write
    ['C-000016', 'already_applied'], // S3: a receipt names the operation
    ['C-000060', 'refusal'], // S23b: an occupied bed
    ['C-000055', 'history_correction'], // S22: a history-of-record receiver
    ['C-000012', 'withheld'], // S15: a merge
    ['C-000013', 'withheld'], // S16: a cancel
  ])('%s gets the %s card, from its recording', (id, variant) => {
    const c = card(id);
    expect(c.variant).toBe(variant);
    expect(c.queueWarning).toContain('may still arrive');
    expect(c.checks[0]!.meanings).toHaveLength(4);
  });

  it('reads a receiver the recording read, dated', () => {
    const c = card('C-000008');
    expect(c.receiverEvidence).toBe('read');
    expect(c.evidenceNote).toMatch(/read at \d{4}-\d\d-\d\d \d\d:\d\d:\d\d UTC/);
    expect(c.receiverRead?.ward).toBe('WARD-C');
    expect(c.laterMovement?.summary).toContain('WARD-C');
  });

  it("names no other patient on a refusal: the occupant's encounter stays out", () => {
    const conflict = JSON.stringify(
      (recorded('C-000060').snapshot?.summary as Record<string, unknown>).bed_conflict,
    );
    const occupant = /"encounter_id":"([^"]+)"/.exec(conflict)?.[1];
    expect(occupant).toBeTruthy();
    expect(JSON.stringify(card('C-000060'))).not.toContain(occupant);
  });

  it('never carries a verified, resend or action field, or the failure text', () => {
    for (const [id, c] of Object.entries(fixtures.cases)) {
      if (!['blocked', 'escalated', 'failed'].includes(c.detail.state)) continue;
      const text = JSON.stringify(card(id));
      expect(text).not.toMatch(/"(verified|safe_to_resend|action|confidence|expected)"/);
      expect(text.toLowerCase()).not.toMatch(/safe to resend|expected result/);
      expect(text).not.toContain(c.detail.failureText);
    }
  });
});
