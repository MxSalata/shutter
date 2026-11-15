import { describe, expect, it } from 'vitest';
import type { SetupProposal, SiteProfile, SiteReceiver } from '@/api/types';
import { coreTable } from '@/test/coreTables';
import { applyBatch, checkTurn, cleanText, draftRefusal, rowAutomatic, textProblem } from './proposals';

/**
 * The web app's copy of the core's checks on a turn (Shutter.Util.ProfileSetup.CheckTurn), held to the core's own table:
 * every row of Shutter.Test.ProfileSetup's TurnRows gives the same answer here, but for the rows about where a quote
 * came from, which only the core can check (it holds what the person typed).
 */

interface Row {
  name: string;
  base?: Partial<SiteProfile>;
  draft?: Partial<SiteProfile>;
  entry?: Partial<SiteReceiver>;
  added?: Partial<SiteReceiver>;
  receiver?: string;
  turn: unknown;
  expect: string;
  accepted?: SetupProposal[];
  core?: boolean;
}

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;

/** The profile in force the rows start from, as Shutter.Test.ProfileSetup.Base gives it. */
const BASE: SiteProfile = {
  receivers: [
    {
      name: 'Downstream Out',
      system: 'the bed manager',
      category: 'current_state',
      tier: 2,
      applies: 'arrival_order',
      resend_timestamp: 'original',
      cancels: false,
      merges: false,
    },
  ],
  policy: {
    '1': { single: 'approval', ordered: 'approval', interleaved: 'board' },
    '2': { single: 'approval', ordered: 'approval', interleaved: 'board' },
    '3': { single: 'approval', ordered: 'per_chain', interleaved: 'board' },
  },
  merges: 'forbidden',
};

/** One row as the profile in force, the draft and the receiver it stands for: the port of the test class's Stage. */
function stage(row: Row) {
  const base: SiteProfile = { ...clone(BASE), ...row.base };
  const draft: SiteProfile = { ...clone(base), ...row.draft };
  Object.assign(draft.receivers[0], row.entry);
  draft.receivers.push({
    name: 'Bed Board',
    features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    ...row.added,
  } as unknown as SiteReceiver);
  return { base, draft, receiver: row.receiver ?? 'Bed Board' };
}

describe('the checks on a turn, the table Shutter.Test.ProfileSetup runs at the server', () => {
  const rows = coreTable<Row>('ProfileSetup', 'TurnRows');

  it('has the rows of the server class', () => {
    expect(rows.length).toBeGreaterThan(30);
  });

  it.each(rows.filter((row) => !row.core).map((row) => [row.name, row] as const))('%s', (_name, row) => {
    const { base, draft, receiver } = stage(row);
    const before = JSON.stringify(draft);
    const checked = checkTurn(row.turn, base, draft, receiver);
    expect(checked.ok ? '' : checked.problem).toBe(row.expect);
    expect(checked.ok).toBe(row.expect === '');
    // The check never changes the draft itself
    expect(JSON.stringify(draft)).toBe(before);
    if (row.accepted && checked.ok) expect(checked.turn.proposals).toEqual(row.accepted);
  });

  it('keeps every refused row out of the draft: a forged field, a policy, a capability, a receiver in force', () => {
    for (const row of rows.filter((r) => r.expect !== '' && !r.core)) {
      const { base, draft, receiver } = stage(row);
      expect([row.name, checkTurn(row.turn, base, draft, receiver).ok]).toEqual([row.name, false]);
    }
  });
});

describe('what Ask Shutter may draft', () => {
  const draft = stage({ name: '', turn: null, expect: '' }).draft;

  it('is a description, and the kind and tier of a receiver being added, and nothing else', () => {
    for (const field of ['receivers[].system', 'receivers[].category', 'receivers[].tier'])
      expect([field, draftRefusal(field, BASE, draft, false)]).toEqual([field, '']);
    // On a receiver in force, the description alone
    expect(draftRefusal('receivers[].system', BASE, draft, true)).toBe('');
    expect(draftRefusal('receivers[].category', BASE, draft, true)).toMatch(
      /only by a person on a receiver in force$/,
    );
    expect(draftRefusal('receivers[].tier', BASE, draft, true)).toMatch(
      /only by a person on a receiver in force$/,
    );
    for (const field of [
      'recovery.mode',
      'policy.1.single',
      'merges',
      'model_content.setup_answers',
      'model_content.free_text',
      'feed.time_zone',
      'receivers[].cancels',
      'receivers[].merges',
      'receivers[].applies',
      'receivers[].api.operations',
      'receivers[].features.dry_run',
      'receivers[].engine_resend',
      'receivers[].name',
    ])
      expect([field, draftRefusal(field, BASE, draft, false)]).toEqual([
        field,
        `.field: ${field} is answered only by a person, with the page's control`,
      ]);
  });

  it('reads a policy row as automatic when any chain kind is released with no person', () => {
    expect(rowAutomatic(BASE, '1')).toBe(false);
    expect(rowAutomatic({ ...BASE, policy: { '1': { interleaved: 'automatic' } } }, '1')).toBe(true);
    expect(rowAutomatic({ ...BASE, policy: {} }, '2')).toBe(false);
  });

  it('applies a batch on a copy, the tier as a number', () => {
    const applied = applyBatch(draft, 'Bed Board', [
      { field: 'receivers[].tier', receiver: 'Bed Board', to: 3, quote: 'tier 3', from: null },
      {
        field: 'receivers[].category',
        receiver: 'Bed Board',
        to: 'orders_results',
        quote: 'lab',
        from: null,
      },
    ]);
    expect(applied.receivers[1]).toMatchObject({ name: 'Bed Board', tier: 3, category: 'orders_results' });
    expect(draft.receivers[1]).not.toHaveProperty('tier');
  });
});

describe('a text refused before it is sent', () => {
  it.each([
    ['see https://intranet.example/boards', 'a link'],
    ['ask www.example.nhs.uk', 'a link'],
    ['mail ward.clerk@example.nhs.uk about it', 'an address'],
    ['its number is 4857261930', 'a run of six or more digits'],
    ['password: hunter2', 'what looks like a credential'],
    ['api key = abc', 'what looks like a credential'],
  ])('%s', (text, what) => {
    expect(textProblem(text)).toBe(what);
    expect(cleanText(text)).toEqual({
      text: '',
      problem: `The text holds ${what}. Take that out and send again: Ask Shutter does not need it.`,
    });
  });

  it('sends a plain answer as typed, line breaks as spaces and the ends trimmed', () => {
    expect(cleanText('  it is the ward\nwhiteboard, tier 2 ')).toEqual({
      text: 'it is the ward whiteboard, tier 2',
      problem: '',
    });
    expect(cleanText('bay 12345, ward 7').problem).toBe('');
    expect(cleanText('   ').problem).toBe('text is required');
    expect(cleanText('a'.repeat(501)).problem).toBe('text is at most 500 characters');
  });
});
