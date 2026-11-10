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
import type { RecoveryControl } from '@/api/types';
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
      return { tone: 'attention', label: 'Not known yet: a person checks', icon: IconQuestionMark };
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
 * The ledger by message (CONTRACTS 17.4 and 17.8): each message once, at its latest row, in the order it first appears.
 * A message a run left unsent and a later run sent is the later row; a later run that sent Shutter's own clone in the
 * origin's place (its header is an earlier row's new header) is the same message. `earlier` holds every row a later one
 * replaced, oldest first. Header ids are compared as text.
 */
export function byMessage(resends: Resend[] | undefined): { latest: Resend[]; earlier: Resend[] } {
  const rows = resends ?? [];
  const alias = new Map<string, string>();
  const at = new Map<string, number>();
  const latest: Resend[] = [];
  const earlier: Resend[] = [];
  rows.forEach((r, i) => {
    const header = String(r.headerId ?? '');
    const key = header ? (alias.get(header) ?? header) : `${r.runId}:${r.position}:${i}`;
    if (r.newHeaderId) alias.set(String(r.newHeaderId), key);
    const was = at.get(key);
    if (was === undefined) {
      at.set(key, latest.length);
      latest.push(r);
    } else {
      earlier.push(latest[was]);
      latest[was] = r;
    }
  });
  return { latest, earlier };
}

/**
 * What the ledger came to, in one line, each message by its latest row: "Shutter's resends: 4 sent, 1 the receiver
 * already held, 2 not sent." Hand closures are counted as such. Empty with no rows.
 */
export function tallyLine(resends: Resend[] | undefined): string {
  const rows = byMessage(resends).latest;
  if (!rows.length) return '';
  const by = (f: (r: Resend) => boolean) => rows.filter(f).length;
  const parts = [
    [by((r) => r.closure === 'sent'), 'sent', 'sent'],
    [by((r) => r.closure === 'already_delivered'), 'the receiver already held', 'the receiver already held'],
    [by((r) => r.closure === 'handled_by_hand'), 'handled by hand', 'handled by hand'],
    [by((r) => r.closure === 'failed'), 'failed', 'failed'],
    [by((r) => r.closure === 'unknown'), 'result not known yet', 'results not known yet'],
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

/**
 * The message that still needs a person after a resend: the last one whose latest row is failed, or unknown (its new
 * header had not settled in the wait, and Shutter reads it again until it does). A message a later row settled (sent,
 * already held, handled by hand) is never it.
 */
export function stoppedBy(resends: Resend[] | undefined): Resend | undefined {
  return byMessage(resends)
    .latest.filter((r) => r.closure === 'failed' || r.closure === 'unknown')
    .at(-1);
}

/** Whether the message that still needs a person after a resend belongs to the latest run (the card says it first then). */
export function stoppedInLatestRun(resends: Resend[] | undefined): boolean {
  const r = stoppedBy(resends);
  return !!r && r.runId === runRows(resends)[0]?.runId;
}

/** The words under a failed or unknown resend: what the engine read, then what happens next, true for its run. */
export function stoppedWords(r: Resend, latestRun: string | undefined): string {
  const read = asSentence(r.words) || 'The engine did not read it as Completed.';
  const next =
    r.runId === latestRun
      ? 'Nothing more was sent; a person reads the trace.'
      : 'That run stopped there; a person reads the trace.';
  const later =
    r.closure === 'unknown'
      ? ' Shutter reads its new header again and settles it here once the engine shows how it ended.'
      : '';
  return `Control id ${r.controlId || 'not read'}: ${read} ${next}${later}`;
}

/**
 * The next sensible "down on purpose until" for the pause field's example: 06:00 UTC on the next morning at least an hour
 * away, as the route takes it ("2026-11-11T06:00:00Z").
 */
export function pauseExample(now: number): string {
  const d = new Date(now + 60 * 60_000);
  const at = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 6);
  const next = at > now + 60 * 60_000 ? at : at + 24 * 60 * 60_000;
  return new Date(next).toISOString().replace(/\.\d+Z$/, 'Z');
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

/**
 * Why the approval is held by the recovery control (CONTRACTS 18), or '' when it isn't: Shutter recovery stopped, or the
 * site in shadow mode, or a control the server says it can't read. The server refuses the approval then (409), so the
 * card says so instead of offering it. Until the control has been read the card offers nothing (OutageCard says it is
 * reading it), so the button never shows first.
 */
export function approvalHeld(
  c: (Pick<RecoveryControl, 'mode' | 'stopped'> & Partial<Pick<RecoveryControl, 'readable'>>) | undefined,
): string {
  if (!c) return '';
  if (c.readable === false)
    return "The recovery control can't be read, so this resend can't be approved now. The messages stay offered: read the card again in a moment, or check Settings.";
  if (c.stopped)
    return "Shutter recovery is stopped, so this resend can't be approved. The messages stay offered: approve them once an approver has cleared the stop in Settings.";
  if (c.mode !== 'enabled')
    return "Shadow mode: recovery is off at this site, so Shutter will not resend these messages. Review them in the Message Viewer using the site's recovery procedure, or enable recovery in the site profile first.";
  return '';
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
    case 'recovery_stopped':
      return `Nothing was sent. ${e.detail || "Shutter recovery is stopped, so this resend can't be approved until an approver clears the stop in Settings."}`;
    case 'recovery_shadow':
      return `Nothing was sent. ${e.detail || 'Shadow mode: recovery is off at this site, so Shutter will not resend these messages.'}`;
    case 'control_unreadable':
      return `Nothing was sent. ${e.detail || 'The recovery control could not be read.'}`;
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

/**
 * The header ids the ledger holds a row for: a message sent, already held, handled by hand or left unsent. Compared as
 * text: the set's rows carry a header id as a number and the ledger's as a string.
 */
function ledgerHeaders(o: Pick<Outage, 'resends'>): Set<string> {
  return new Set((o.resends ?? []).map((r) => String(r.headerId ?? '')).filter(Boolean));
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
  return o.lists.offered.filter((r) => !done.has(String(r.headerId)));
}

/** The messages closed with no send of their own that the ledger does not already list (it lists each hand closure). */
export function closedRowsToShow(o: Pick<Outage, 'lists' | 'resends'>): OutageRow[] {
  const done = ledgerHeaders(o);
  return (o.lists.closed ?? []).filter((r) => !done.has(String(r.headerId)));
}
