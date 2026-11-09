import {
  IconAlertCircle,
  IconCopyCheck,
  IconClock,
  IconHandStop,
  IconLoader2,
  IconMinus,
  IconQuestionMark,
  IconSend,
  IconTool,
  type Icon,
} from '@tabler/icons-react';
import { isApiError } from '@/lib/errors';
import type { Tone } from '@/lib/tone';
import type { Outage, OutageRow, Resend } from './types';

/*
 * The outage card's words for the send (CONTRACTS 17.8): pure, so a table test holds them. Sending is an action taken,
 * not a result verified, so a sent message is information, never green; a failed one is blocking; a message closed
 * because the receiver already holds it, or because a person entered it by hand, is a decision with nothing waiting.
 */

export interface ResendStatus {
  tone: Tone;
  label: string;
  icon: Icon;
}

/** How one row of the ledger stands, by its closure and, while it has none, its state. */
export function resendStatus(r: Pick<Resend, 'state' | 'closure'>): ResendStatus {
  switch (r.closure) {
    case 'sent':
      return { tone: 'info', label: 'Sent', icon: IconSend };
    case 'already_delivered':
      return { tone: 'neutral', label: 'Already delivered', icon: IconCopyCheck };
    case 'handled_by_hand':
      return { tone: 'neutral', label: 'Handled by hand', icon: IconTool };
    case 'failed':
      return { tone: 'blocking', label: 'Failed', icon: IconAlertCircle };
    case 'unknown':
      return { tone: 'attention', label: 'Unknown: a person checks', icon: IconQuestionMark };
  }
  switch (r.state) {
    case 'approved':
      return { tone: 'neutral', label: 'Waiting to send', icon: IconClock };
    case 'sending':
      return { tone: 'info', label: 'Sending now', icon: IconLoader2 };
    case 'stopped':
      return { tone: 'neutral', label: 'Not sent', icon: IconHandStop };
    default:
      return { tone: 'neutral', label: r.state.replace(/_/g, ' '), icon: IconMinus };
  }
}

/** A row of `lists.closed`: why the message needs no send. */
export function closureLabel(closure: string | null | undefined): string {
  if (closure === 'already_delivered') return 'Already delivered';
  if (closure === 'handled_by_hand') return 'Handled by hand';
  return 'Closed';
}

/** The rows of the approval's run: the latest run Shutter sent (`R...`), not the hand closures (`H...`). */
export function runRows(resends: Resend[] | undefined): Resend[] {
  const rows = resends ?? [];
  const run = rows.filter((r) => !r.runId.startsWith('H')).at(-1)?.runId;
  return run ? rows.filter((r) => r.runId === run) : [];
}

/** While sending: "Sending 2 of 5, one at a time, in order." Empty when no run is under way. */
export function sendingLine(o: Pick<Outage, 'state' | 'resends'>): string {
  if (o.state !== 'sending') return '';
  const rows = runRows(o.resends);
  if (!rows.length) return 'Sending, one at a time, in order.';
  const done = rows.filter((r) => r.closure).length;
  const now = rows.some((r) => r.state === 'sending') ? done + 1 : done;
  return `Sending ${Math.max(now, 1)} of ${rows.length}, one at a time, in order.`;
}

const count = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/**
 * What the ledger came to, in one line: "Shutter's resends: 4 sent, 1 the receiver already held, 2 not sent." Hand
 * closures are counted as such. Empty with no rows.
 */
export function tallyLine(resends: Resend[] | undefined): string {
  const rows = resends ?? [];
  if (!rows.length) return '';
  const by = (f: (r: Resend) => boolean) => rows.filter(f).length;
  const parts = [
    [by((r) => r.closure === 'sent'), 'sent', 'sent'],
    [by((r) => r.closure === 'already_delivered'), 'the receiver already held', 'the receiver already held'],
    [by((r) => r.closure === 'handled_by_hand'), 'handled by hand', 'handled by hand'],
    [by((r) => r.closure === 'failed'), 'failed', 'failed'],
    [by((r) => r.closure === 'unknown'), 'unknown', 'unknown'],
    [by((r) => r.state === 'stopped'), 'not sent', 'not sent'],
    [
      by((r) => !r.closure && (r.state === 'approved' || r.state === 'sending')),
      'still to send',
      'still to send',
    ],
  ] as const;
  const said = parts.filter(([n]) => n > 0).map(([n, one, many]) => `${n} ${n === 1 ? one : many}`);
  return said.length ? `Shutter's resends: ${said.join(', ')}.` : '';
}

/** The run's row that stopped it: the last failed or unknown one, if any. */
export function stoppedBy(resends: Resend[] | undefined): Resend | undefined {
  return (resends ?? []).filter((r) => r.closure === 'failed' || r.closure === 'unknown').at(-1);
}

/**
 * Whether the approval needs the receiver checked first (17.8): the receiver does not refuse duplicates, which the route
 * says by offering "already handled by hand" on the offered rows and the outage.
 */
export function needsReceiverCheck(o: Pick<Outage, 'acts' | 'lists'>): boolean {
  return (
    o.acts.includes('handled_by_hand') || o.lists.offered.some((r) => r.acts?.includes('handled_by_hand'))
  );
}

/** Whether a person with the approver role is offered the approval now. */
export function canApprove(o: Pick<Outage, 'state' | 'approvable' | 'set' | 'lists'>): boolean {
  return (
    o.state === 'offered' &&
    o.approvable &&
    o.set.status === 'computed' &&
    !!o.set.digest &&
    o.lists.offered.length > 0
  );
}

/** The approval's consequence, first in its dialog. */
export function approveConsequence(o: Pick<Outage, 'receiver' | 'lists'>): string {
  const n = o.lists.offered.length;
  return `This has the engine send ${n === 1 ? 'this message' : `these ${n} messages`} to ${o.receiver} again, one at a time, in this order: each is the stored message, unchanged.`;
}

/** The server's detail after a colon: its first letter lowered, unless it starts an acronym ("HL7", "MSA"). */
const afterColon = (t: string) => (/^[A-Z][a-z]/.test(t) ? `${t[0].toLowerCase()}${t.slice(1)}` : t);

/** A refused approval or act in plain words: what happened, and that nothing was sent. */
export function refusalWords(e: unknown): string {
  if (!isApiError(e)) return 'Nothing was sent: the server could not be reached.';
  const detail = afterColon(e.detail);
  switch (e.code) {
    case 'set_changed':
      return 'Nothing was sent: the list changed since you read it. Read the new list and approve what it lists now.';
    case 'version_changed':
      return 'Nothing was sent: the outage moved on since you read it. Read it again.';
    case 'receiver_check_needed':
      return `Nothing was sent: ${detail || 'check the receiver for these messages first, and say so with the approval.'}`;
    case 'wrong_state':
      return `Nothing was sent: ${detail || 'the outage is no longer offered.'}`;
    case 'not_approvable':
      return `Nothing was sent: ${detail || 'this receiver is not set up for a resend.'}`;
    default:
      return `Nothing was sent: ${detail || afterColon(e.message)}`;
  }
}

/** The approval's line while it stands or its run goes: "Approved by approver at ... for 5 messages." */
export function approvedLine(o: Pick<Outage, 'approval' | 'resends'>): string {
  if (!o.approval) return '';
  const n = runRows(o.resends).length;
  return `Approved by ${o.approval.by}${n ? ` for ${count(n, 'message', 'messages')}` : ''}`;
}

/** The server's words as a sentence: the first letter raised and a full stop at the end ("not sent: ..." reads "Not sent: ..."). */
export function asSentence(words: string | null | undefined): string {
  const t = (words ?? '').trim();
  if (!t) return '';
  return `${t[0].toUpperCase()}${t.slice(1)}${/[.!?]$/.test(t) ? '' : '.'}`;
}

/** The always-on reading in words, as a badge says it: "Can't tell", "Not answering". */
export function readingLabel(reading: string): string {
  const words: Record<string, string> = {
    healthy: 'Healthy',
    slow: 'Slow',
    down: 'Down',
    refusing: 'Refusing',
    not_answering: 'Not answering',
    cant_tell: "Can't tell",
    unknown: 'Unknown',
  };
  return words[reading] ?? asSentence(reading.replace(/_/g, ' ')).replace(/\.$/, '');
}

/** The header ids the ledger holds a row for: a message sent, already held, handled by hand or left unsent. */
function ledgerHeaders(o: Pick<Outage, 'resends'>): Set<string> {
  return new Set((o.resends ?? []).map((r) => r.headerId ?? '').filter(Boolean));
}

/**
 * The offered list as the card shows it. While offered it is the set just computed, whole. While a run is sending it is
 * not shown (the ledger shows the run); after a run the list was read before it, so a message the ledger holds a row for
 * is left out, and a sent message is never still listed as evidence to review before any resend.
 */
export function offeredRowsToShow(o: Pick<Outage, 'state' | 'lists' | 'resends'>): OutageRow[] {
  if (o.state === 'offered') return o.lists.offered;
  if (o.state === 'sending') return [];
  const done = ledgerHeaders(o);
  return o.lists.offered.filter((r) => !done.has(r.headerId));
}

/** The messages closed with no send of their own that the ledger does not already list (it lists each hand closure). */
export function closedRowsToShow(o: Pick<Outage, 'lists' | 'resends'>): OutageRow[] {
  const done = ledgerHeaders(o);
  return (o.lists.closed ?? []).filter((r) => !done.has(r.headerId));
}
