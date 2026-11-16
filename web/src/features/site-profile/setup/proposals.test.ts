import { describe, expect, it } from 'vitest';
import type { SetupProposal, SiteEntryItem, SiteProfile, SiteReceiver } from '@/api/types';
import { coreTable } from '@/test/coreTables';
import {
  applyBatch,
  checkTurn,
  cleanText,
  draftRefusal,
  effectsRefusal,
  kindReadBy,
  nameProblem,
  rowAutomatic,
  textProblem,
} from './proposals';
import { whyFocus } from './cards';
import { QUESTIONS } from './fields';

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

describe('the effects check on its own, as Shutter.Test.ProfileSetup:TestTheEffectsCheck holds the core to it', () => {
  it('refuses a batch that makes a tier release single failures with no person, against the profile in force or the draft', () => {
    const automatic = (p: SiteProfile): SiteProfile => ({
      ...p,
      policy: { ...p.policy, '2': { ...p.policy!['2'], single: 'automatic' } },
    });
    expect(effectsRefusal(BASE, clone(BASE), automatic(clone(BASE)), 'Downstream Out')).toBe(
      "proposals: less strict than the profile in force: a resend of single failures would need no person's approval",
    );
    expect(effectsRefusal(BASE, clone(BASE), clone(BASE), 'Downstream Out')).toBe('');
    const draft = clone(BASE);
    draft.receivers.push({
      name: 'Bed Board',
      tier: 2,
      features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
    } as unknown as SiteReceiver);
    expect(effectsRefusal(BASE, draft, automatic(clone(draft)), 'Bed Board')).toBe(
      "proposals: less strict than the draft: a resend of single failures would need no person's approval",
    );
  });
});

describe('what Ask Shutter may draft', () => {
  const draft = stage({ name: '', turn: null, expect: '' }).draft;
  const added = draft.receivers[1];

  it("is no kind while one of the site's own active entries reads the kind, as the core refuses it", () => {
    const entry = (
      state: string,
      pattern: Record<string, string[]>,
      effectivePattern?: Record<string, string[]>,
    ) =>
      ({
        state,
        content: { pattern },
        ...(effectivePattern ? { effectivePattern } : {}),
      }) as unknown as SiteEntryItem;
    const reads = entry('active', { event: ['merge'], receiver_category: ['current_state'] });
    expect(kindReadBy([reads])).toBe(true);
    expect(kindReadBy([entry('suspended', { receiver_category: ['current_state'] })])).toBe(false);
    expect(kindReadBy([entry('active', { event: ['merge'] })])).toBe(false);
    // A recheck that dropped the condition leaves a pattern in force that no longer reads it
    expect(
      kindReadBy([entry('active', { receiver_category: ['current_state'] }, { event: ['merge'] })]),
    ).toBe(false);
    expect(draftRefusal('receivers[].category', BASE, draft, false, added, undefined, false, true)).toBe(
      ".field: receivers[].category is answered only by a person while one of the site's own entries reads the kind (receiver_category)",
    );
    expect(draftRefusal('receivers[].tier', BASE, draft, false, added, undefined, false, true)).toBe('');
    const turn = {
      say: 'It keeps every movement in order.',
      proposals: [
        {
          field: 'receivers[].category',
          receiver: 'Bed Board',
          to: 'history_of_record',
          quote: 'it keeps every movement in order',
        },
      ],
    };
    const typed = stage({ name: '', turn: null, expect: '' });
    expect(checkTurn(turn, typed.base, typed.draft, 'Bed Board', true)).toEqual({
      ok: false,
      problem:
        "proposals[0].field: receivers[].category is answered only by a person while one of the site's own entries reads the kind (receiver_category)",
    });
  });

  it('is a description, and the kind and tier of a receiver being added, and nothing else', () => {
    for (const field of ['receivers[].system', 'receivers[].category', 'receivers[].tier'])
      expect([field, draftRefusal(field, BASE, draft, false, added)]).toEqual([field, '']);
    // On a receiver in force, the description alone
    const own = draft.receivers[0];
    expect(draftRefusal('receivers[].system', BASE, draft, true, own)).toBe('');
    expect(draftRefusal('receivers[].category', BASE, draft, true, own)).toMatch(
      /only by a person on a receiver in force$/,
    );
    expect(draftRefusal('receivers[].tier', BASE, draft, true, own)).toMatch(
      /only by a person on a receiver in force$/,
    );
    // A kind or a tier the draft already answers is a person's to change, whoever gave it
    for (const [field, entry] of [
      ['receivers[].category', { ...added, category: 'history_of_record' }],
      ['receivers[].tier', { ...added, tier: 3 }],
    ] as const)
      expect(draftRefusal(field, BASE, draft, false, entry as SiteReceiver)).toBe(
        `.field: ${field} is answered in the draft: only a person changes it, with the page's control`,
      );
    expect(draftRefusal('receivers[].system', BASE, draft, false, { ...added, system: 'a board' })).toBe('');
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
      expect([field, draftRefusal(field, BASE, draft, false, added)]).toEqual([
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

describe('a text refused before it is sent, the table Shutter.Test.ProfileSetup runs at the server', () => {
  // A text given as parts is the parts joined, so no whole token shape stands in the table's file
  const rows = coreTable<[string | string[], string]>('ProfileSetup', 'TextRows').map(
    ([text, what]) => [Array.isArray(text) ? text.join('') : text, what] as const,
  );

  it('has the rows of the server class', () => {
    expect(rows.length).toBeGreaterThan(30);
    expect(rows.filter(([, what]) => what).length).toBeGreaterThan(20);
  });

  it.each(rows.map(([text, what]) => [JSON.stringify(text).slice(0, 50), text, what] as const))(
    '%s',
    (_label, text, what) => {
      expect(textProblem(text)).toBe(what);
      expect(cleanText(text).problem).toBe(
        what ? `The text holds ${what}. Take that out and send again: Ask Shutter does not need it.` : '',
      );
    },
  );

  it('reads a dash as a hyphen, and refuses a text longer than the bound before any pattern reads it', () => {
    expect(cleanText('the ward \u2013 bay 4')).toEqual({ text: 'the ward - bay 4', problem: '' });
    const long = 'z'.repeat(400_000);
    const t0 = performance.now();
    expect(textProblem(long)).toBe('more than 2000 characters');
    expect(performance.now() - t0).toBeLessThan(1000);
    expect(textProblem(long.slice(0, 2000))).toBe('');
    expect(nameProblem(long.slice(0, 2001))).toContain('more than 2000 characters');
  });

  it("refuses a receiver's name that fails the same rule", () => {
    expect(nameProblem('Bed Board')).toBe('');
    expect(nameProblem('Ward 7, ask j.smith@trust.nhs.uk')).toBe(
      "The receiver's name holds an address. Ask Shutter reads typed answers only about a receiver whose name has none: change the name, or answer with the page's controls.",
    );
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

describe('"Why does this matter?" on Set up the site', () => {
  const system = QUESTIONS.find((q) => q.id === 'system')!;
  const name = QUESTIONS.find((q) => q.id === 'name')!;

  it("sends the receiver's name and the answer only when they pass the text rule, whatever the site's switch", () => {
    const plain = { name: 'Bed Board', system: 'the ward whiteboard' } as SiteReceiver;
    expect(whyFocus(system, plain, BASE)).toMatchObject({ answer: 'the ward whiteboard' });
    expect(whyFocus(system, plain, BASE).question).toContain('about Bed Board');
    // The review's case: a description typed with the control, with an address in it
    const loud = { name: 'Bed Board', system: 'Ward 7 board, ask j.smith@trust.nhs.uk' } as SiteReceiver;
    const focus = whyFocus(system, loud, BASE);
    expect(focus.answer).toBe('Not sent: the answer holds an address');
    expect(JSON.stringify(focus)).not.toContain('j.smith');
    const badName = { name: 'Ward 7, ask j.smith@trust.nhs.uk', system: 'the board' } as SiteReceiver;
    for (const q of [system, name]) {
      const f = whyFocus(q, badName, BASE);
      expect(JSON.stringify(f)).not.toContain('j.smith');
      expect(f.question).toContain('about this receiver');
    }
  });
});
