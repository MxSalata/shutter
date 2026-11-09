import { describe, expect, it } from 'vitest';
import { ApiError } from '@/lib/errors';
import {
  asSentence,
  canApprove,
  closedRowsToShow,
  closureLabel,
  needsReceiverCheck,
  offeredRowsToShow,
  readingLabel,
  refusalWords,
  resendStatus,
  runRows,
  sendingLine,
  stoppedBy,
  tallyLine,
} from './outageWords';
import type { Outage, Resend } from './types';

const row = (position: number, state: string, closure: string | null, runId = 'R7-4'): Resend => ({
  runId,
  position,
  headerId: String(40 + position),
  controlId: `C${position}`,
  state,
  closure,
});

const lists = (offered: Outage['lists']['offered'] = []): Outage['lists'] => ({
  queued: [],
  offered,
  reached: [],
  refused: [],
  closed: [],
});

describe("the send's words", () => {
  it('gives each row of the ledger its tone and words: sent is information, failed blocking, closures neutral', () => {
    const table: [string, string | null, string, string][] = [
      ['completed', 'sent', 'info', 'Sent'],
      ['closed_as_present', 'already_delivered', 'neutral', 'Already delivered'],
      ['handled_by_hand', 'handled_by_hand', 'neutral', 'Handled by hand'],
      ['failed', 'failed', 'blocking', 'Failed'],
      ['unknown', 'unknown', 'attention', 'Unknown: a person checks'],
      ['approved', null, 'neutral', 'Waiting to send'],
      ['sending', null, 'info', 'Sending now'],
      ['stopped', null, 'neutral', 'Not sent'],
    ];
    for (const [state, closure, tone, label] of table)
      expect(resendStatus({ state, closure }), state).toMatchObject({ tone, label });
    expect(closureLabel('already_delivered')).toBe('Already delivered');
    expect(closureLabel('handled_by_hand')).toBe('Handled by hand');
  });

  it("counts the run's progress and its tally from the ledger, leaving hand closures out of the run", () => {
    const resends = [
      row(1, 'completed', 'sent'),
      row(2, 'sending', null),
      row(3, 'approved', null),
      { ...row(0, 'handled_by_hand', 'handled_by_hand', 'H7'), headerId: '50' },
    ];
    expect(runRows(resends)).toHaveLength(3);
    expect(sendingLine({ state: 'sending', resends })).toBe('Sending 2 of 3, one at a time, in order.');
    expect(sendingLine({ state: 'offered', resends })).toBe('');
    expect(tallyLine(resends)).toBe("Shutter's resends: 1 sent, 1 handled by hand, 2 still to send.");
    const ended = [
      row(1, 'completed', 'sent'),
      row(2, 'closed_as_present', 'already_delivered'),
      row(3, 'failed', 'failed'),
      row(4, 'stopped', null),
    ];
    expect(tallyLine(ended)).toBe(
      "Shutter's resends: 1 sent, 1 the receiver already held, 1 failed, 1 not sent.",
    );
    expect(stoppedBy(ended)?.controlId).toBe('C3');
    expect(stoppedBy([row(1, 'completed', 'sent')])).toBeUndefined();
    expect(tallyLine([])).toBe('');
  });

  it('asks for the receiver check only where the route offers already handled by hand', () => {
    const offered = {
      headerId: '41',
      controlId: 'CA',
      timeCreated: '',
      status: 'Error',
      attempts: '',
      reason: '',
    };
    expect(needsReceiverCheck({ acts: ['pause', 'close'], lists: lists([{ ...offered, acts: [] }]) })).toBe(
      false,
    );
    expect(
      needsReceiverCheck({
        acts: ['pause', 'close'],
        lists: lists([{ ...offered, acts: ['handled_by_hand'] }]),
      }),
    ).toBe(true);
    expect(needsReceiverCheck({ acts: ['handled_by_hand'], lists: lists() })).toBe(true);
  });

  it('offers the approval only on an offered, approvable, computed set with something in it', () => {
    const offered = {
      headerId: '41',
      controlId: 'CA',
      timeCreated: '',
      status: 'Error',
      attempts: '',
      reason: '',
    };
    const base = {
      state: 'offered',
      approvable: true,
      set: { status: 'computed', digest: 'abc' },
      lists: lists([offered]),
    };
    expect(canApprove(base)).toBe(true);
    expect(canApprove({ ...base, approvable: false })).toBe(false);
    expect(canApprove({ ...base, state: 'sending' })).toBe(false);
    expect(canApprove({ ...base, set: { status: 'not_computed' } })).toBe(false);
    expect(canApprove({ ...base, lists: lists() })).toBe(false);
  });

  it('says a refusal in plain words, and that nothing was sent', () => {
    const refused = (error: string, detail = '') =>
      refusalWords(
        new ApiError({ status: 409, method: 'POST', path: '/outages/7/approvals', body: { error, detail } }),
      );
    expect(refused('set_changed')).toBe(
      'Nothing was sent: the list changed since you read it. Read the new list and approve what it lists now.',
    );
    expect(
      refused('receiver_check_needed', 'At this receiver a duplicate is unknown: check the receiver first.'),
    ).toBe('Nothing was sent: at this receiver a duplicate is unknown: check the receiver first.');
    expect(refused('version_changed')).toMatch(/^Nothing was sent: the outage moved on/);
    expect(refusalWords(new Error('offline'))).toBe('Nothing was sent: the server could not be reached.');
  });

  it("reads the server's words as a sentence", () => {
    expect(asSentence('not sent: the run stopped')).toBe('Not sent: the run stopped.');
    expect(asSentence('Already delivered: it holds it.')).toBe('Already delivered: it holds it.');
    expect(asSentence(null)).toBe('');
  });
});

describe('what the card lists', () => {
  const offered = (id: string) =>
    ({ headerId: id, controlId: `C${id}` }) as Outage['lists']['offered'][number];
  const set = { ...lists([offered('41'), offered('42'), offered('43')]) };

  it('lists the offered set whole while it is offered, nothing while it sends, and after a run only what the ledger lacks', () => {
    const resends = [row(1, 'completed', 'sent'), row(2, 'stopped', null)];
    const ids = (state: string) => offeredRowsToShow({ state, lists: set, resends }).map((r) => r.headerId);
    expect(ids('offered')).toEqual(['41', '42', '43']);
    expect(ids('sending')).toEqual([]);
    expect(ids('needs_person')).toEqual(['43']);
    expect(ids('closed')).toEqual(['43']);
  });

  it("matches a header the set gives as a number with the ledger's string", () => {
    const numbers = lists(
      [41, 43].map(
        (n) => ({ headerId: n, controlId: `C${n}` }) as unknown as Outage['lists']['offered'][number],
      ),
    );
    const left = offeredRowsToShow({
      state: 'closed',
      lists: numbers,
      resends: [row(1, 'completed', 'sent')],
    });
    expect(left.map((r) => String(r.headerId))).toEqual(['43']);
  });

  it('leaves a closed message out where the ledger lists it', () => {
    const closed = { ...set, closed: [offered('41'), offered('49')] };
    expect(
      closedRowsToShow({ lists: closed, resends: [row(1, 'handled_by_hand', 'handled_by_hand', 'H7')] }),
    ).toEqual([offered('49')]);
  });

  it("says a reading in words: Can't tell, Not answering", () => {
    expect(readingLabel('cant_tell')).toBe("Can't tell");
    expect(readingLabel('not_answering')).toBe('Not answering');
    expect(readingLabel('healthy')).toBe('Healthy');
    expect(readingLabel('something_new')).toBe('Something new');
  });
});
