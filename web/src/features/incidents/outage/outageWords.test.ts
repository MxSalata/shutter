import { describe, expect, it } from 'vitest';
import { ApiError } from '@/lib/errors';
import {
  approvalHeld,
  asSentence,
  byMessage,
  canApprove,
  closedRowsToShow,
  closureLabel,
  needsReceiverCheck,
  offeredRowsToShow,
  pauseExample,
  readingLabel,
  refusalWords,
  resendStatus,
  runRows,
  sendingLine,
  stoppedBy,
  stoppedInLatestRun,
  stoppedWords,
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
      ['unknown', 'unknown', 'attention', 'Not known yet: a person checks'],
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

  it('reads each message by its latest row across runs, as the 1.4.0 recheck found it was not', () => {
    // The recheck's outage: run 1 sent G6S1, whose answer came after the settle window, and left four unsent; run 2 sent
    // one and halted at the stop; run 3 sent the last three. Engine Resend then read G6S1's new header Completed.
    const g = (
      runId: string,
      position: number,
      header: number,
      state: string,
      closure: string | null,
      extra = {},
    ) => ({
      ...row(position, state, closure, runId),
      headerId: String(header),
      controlId: `G6S${header - 40}`,
      ...extra,
    });
    const run1 = [
      g('R3-3', 1, 41, 'unknown', 'unknown', {
        newHeaderId: '328',
        words: 'new header 328 had not settled in 15 s (unread)',
      }),
      g('R3-3', 2, 42, 'stopped', null),
      g('R3-3', 3, 43, 'stopped', null),
      g('R3-3', 4, 44, 'stopped', null),
      g('R3-3', 5, 45, 'stopped', null),
    ];
    const run2 = [
      g('R3-5', 1, 42, 'completed', 'sent', { newHeaderId: '329' }),
      g('R3-5', 2, 43, 'stopped', null, { halt: 'recovery_stopped' }),
      g('R3-5', 3, 44, 'stopped', null, { halt: 'recovery_stopped' }),
      g('R3-5', 4, 45, 'stopped', null, { halt: 'recovery_stopped' }),
    ];
    const run3 = [
      g('R3-8', 1, 43, 'completed', 'sent', { newHeaderId: '330' }),
      g('R3-8', 2, 44, 'completed', 'sent', { newHeaderId: '331' }),
      g('R3-8', 3, 45, 'completed', 'sent', { newHeaderId: '332' }),
    ];
    const still = [...run1, ...run2, ...run3];
    expect(byMessage(still).latest.map((r) => `${r.controlId}:${r.state}`)).toEqual([
      'G6S1:unknown',
      'G6S2:completed',
      'G6S3:completed',
      'G6S4:completed',
      'G6S5:completed',
    ]);
    expect(byMessage(still).earlier).toHaveLength(7);
    expect(tallyLine(still)).toBe("Shutter's resends: 4 sent, 1 result not known yet.");
    expect(stoppedBy(still)?.controlId).toBe('G6S1');
    expect(stoppedInLatestRun(still)).toBe(false);
    expect(stoppedWords(stoppedBy(still)!, 'R3-8')).toBe(
      'Control id G6S1: New header 328 had not settled in 15 s (unread). That run stopped there; a person reads the trace. Shutter reads its new header again and settles it here once the engine shows how it ended.',
    );
    // Once Engine Resend has read its new header Completed, nothing on the card still needs a person
    const settled = [
      {
        ...run1[0],
        state: 'completed',
        closure: 'sent',
        words: 'Resent by Shutter; new header 328 Completed, read at 01:47.',
      },
      ...still.slice(1),
    ];
    expect(tallyLine(settled)).toBe("Shutter's resends: 5 sent.");
    expect(stoppedBy(settled)).toBeUndefined();
    // A later run that sent Shutter's own clone in the origin's place is the same message
    const clone = [
      { ...row(1, 'unknown', 'unknown', 'R1-2'), newHeaderId: '91' },
      { ...row(1, 'completed', 'sent', 'R1-4'), headerId: '91', newHeaderId: '94' },
    ];
    expect(byMessage(clone).latest).toHaveLength(1);
    expect(tallyLine(clone)).toBe("Shutter's resends: 1 sent.");
    // The latest run's own failure is said as it was: nothing more went
    const failed = [
      row(1, 'completed', 'sent'),
      { ...row(2, 'failed', 'failed'), words: 'new header 902 ended Suspended' },
    ];
    expect(stoppedInLatestRun(failed)).toBe(true);
    expect(stoppedWords(stoppedBy(failed)!, 'R7-4')).toBe(
      'Control id C2: New header 902 ended Suspended. Nothing more was sent; a person reads the trace.',
    );
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
    // The recovery control's words keep their capital: "Shutter" and "Shadow" start a sentence of their own
    expect(
      refused('recovery_stopped', "Shutter recovery is stopped, so this resend can't be approved."),
    ).toBe("Nothing was sent. Shutter recovery is stopped, so this resend can't be approved.");
    expect(refused('recovery_shadow')).toMatch(/^Nothing was sent\. Shadow mode: recovery is off/);
  });

  it('holds the approval while recovery is stopped or in shadow mode, and only then', () => {
    expect(approvalHeld({ mode: 'enabled', stopped: false })).toBe('');
    expect(approvalHeld(undefined)).toBe('');
    expect(approvalHeld({ mode: 'enabled', stopped: true })).toMatch(/^Shutter recovery is stopped/);
    expect(approvalHeld({ mode: 'shadow', stopped: true })).toMatch(/^Shutter recovery is stopped/);
    expect(approvalHeld({ mode: 'shadow', stopped: false })).toMatch(/^Shadow mode: recovery is off/);
    expect(approvalHeld({ mode: 'enabled', stopped: false, readable: false })).toMatch(
      /^The recovery control can't be read, so this resend can't be approved now/,
    );
  });

  it('gives the pause field an example always ahead: the next 06:00 UTC at least an hour away', () => {
    expect(pauseExample(Date.parse('2026-11-10T09:05:00Z'))).toBe('2026-11-11T06:00:00Z');
    expect(pauseExample(Date.parse('2026-11-10T03:00:00Z'))).toBe('2026-11-10T06:00:00Z');
    expect(pauseExample(Date.parse('2026-11-10T05:30:00Z'))).toBe('2026-11-11T06:00:00Z');
    expect(pauseExample(Date.parse('2026-11-10T23:30:00Z'))).toBe('2026-11-11T06:00:00Z');
    expect(pauseExample(Date.parse('2026-12-31T22:00:00Z'))).toBe('2027-01-01T06:00:00Z');
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
