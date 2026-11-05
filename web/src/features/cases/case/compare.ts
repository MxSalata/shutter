import type { AttemptView, CaseDetail, CaseSummary, Closure, PlanView, Snapshot } from '@/api/types';
import { asArray, asObject } from '@/lib/json';
import { displayZone, formatZoned, humanize } from '@/lib/format';
import type { PlayedResult } from '@/lib/proof';
import type { OutcomeCase } from '@/lib/status';
import type { Tone } from '@/lib/tone';
import { WRITE_OUTCOMES } from './receipt';
import { encounterTimeline, type TimelineRow } from './timeline';

/**
 * S8 played twice, side by side: rules alone and the board on the same failure. Each side is read from the API's own
 * answers for its case (the case, plan, attempts, closure and snapshot), so the comparison works on an instance and
 * in the demo alike. Kept apart from the panel to be tested.
 */

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));
const newestFirst = (a: CaseSummary, b: CaseSummary) => b.openedAt.localeCompare(a.openedAt);

/** The latest S8 case played in Rules only mode and the latest played in board mode, when there are such. */
export function s8Pair(cases: CaseSummary[]): { rules?: CaseSummary; board?: CaseSummary } {
  const s8 = cases.filter((c) => c.scenario === 'S8').sort(newestFirst);
  return { rules: s8.find((c) => c.mode === 'rules'), board: s8.find((c) => c.mode === 'board') };
}

/** The facts both sides' evidence holds, in words, to be read across. */
export interface EvidenceFacts {
  failed: string;
  sameTime: string;
  receiver: string;
  receipt: string;
  laterEvents: string;
  takenAt: string;
  snapshotDigest: string;
  materialDigest: string;
}

export interface CompareSide {
  caseId: string;
  mode: string;
  state: string;
  disposition: string;
  catalogueEntry: string;
  /** What the case's outcome is read from, with the writes and verification this side found. */
  outcome: OutcomeCase;
  /** How it ended for the patient, the card's headline; empty when the writes leave that unknown. */
  patient: string;
  /** What happened at the receiver, in one line. */
  result: string;
  writes: number;
  verification: string;
  /** The first disagreement the plan kept, when it kept one: a member that said otherwise, and why it was overruled. */
  dissent: string;
  planSummary: string;
  evidence: EvidenceFacts | null;
}

function operation(r: TimelineRow): string {
  return `${r.system} ${humanize(r.event).toLowerCase()}${r.ward ? ` to ${r.ward}` : ''} at ${formatZoned(r.eventTime)}`;
}

export function evidenceFacts(snapshot: Snapshot | null | undefined): EvidenceFacts | null {
  if (!snapshot) return null;
  const s = asObject(snapshot.summary) ?? {};
  const rows = encounterTimeline(s, displayZone());
  const own = rows.find((r) => r.thisCase);
  const others = own ? rows.filter((r) => !r.thisCase && r.sameTime && r.eventTime === own.eventTime) : [];
  const ward = asObject(s.ward_state) ?? {};
  const receiptStatus = Number(s.receipt_http_status);
  return {
    failed: own
      ? `${operation(own)}: ${humanize(own.outcome).toLowerCase()}${own.httpStatus ? ` (HTTP ${own.httpStatus})` : ''}`
      : '',
    sameTime: others.length
      ? others
          .map(
            (o) =>
              `${operation(o)}: ${humanize(o.outcome).toLowerCase()}${o.versionAfter ? `, version ${o.versionAfter}` : ''}`,
          )
          .join('; ')
      : 'none',
    receiver: ward.ward ? `${str(ward.ward)} at version ${str(ward.version)}` : 'not read',
    receipt:
      receiptStatus === 404
        ? 'none: never committed'
        : receiptStatus === 200
          ? 'committed'
          : `unknown (HTTP ${str(s.receipt_http_status) || 'none'})`,
    laterEvents: String(asArray(s.later_events).length || Number(s.later_events) || 0),
    takenAt: snapshot.takenAt,
    snapshotDigest: snapshot.digest,
    materialDigest: str(snapshot.materialDigest),
  };
}

/**
 * Where the run left the patient, so a reader doesn't have to work it out from versions and receipts. The ward the
 * receiver held when observed is the bed manager's: on S8, the only scenario compared here, its transfer is what landed.
 */
function patientLine(written: string, before: string, sent: number): string {
  if (written)
    return before && before !== written
      ? `Patient ends in ${written}, over the bed manager's ${before}`
      : `Patient ends in ${written}`;
  // A write went out and none is confirmed: where the patient is stays for the verifier to say
  if (sent || !before) return '';
  return `Patient stays in ${before}; a person decides`;
}

export function compareSide({
  c,
  plan,
  attempts,
  closure,
  snapshot,
}: {
  c: CaseDetail;
  plan: PlanView | null | undefined;
  attempts: AttemptView[] | null | undefined;
  closure: Closure | null | undefined;
  snapshot: Snapshot | null | undefined;
}): CompareSide {
  const p = plan?.plan;
  const evidence = evidenceFacts(snapshot);
  const sent = (attempts ?? []).filter((x) => WRITE_OUTCOMES.includes(str(x.attempt?.outcome)));
  const written = sent.map((x) => asObject(x.attempt?.receipt)).find((r) => r && r.ward);
  const verified =
    [...(attempts ?? [])].reverse().find((x) => x.verification)?.verification ?? closure?.verification;
  const before = asObject(asObject(snapshot?.summary)?.ward_state)?.ward;
  const result = written
    ? `Wrote ${str(written.ward)}${before ? ` over ${str(before)}` : ''}: version ${str(written.version_before)} to ${str(written.version_after)}`
    : sent.length
      ? `${sent.length} write${sent.length === 1 ? '' : 's'} sent, none committed`
      : `${humanize(p?.disposition || c.disposition)}${p?.catalogueEntry ? `, citing ${p.catalogueEntry}` : ''}; no write`;
  const dissent = asObject(asArray(p?.disagreements)[0]);
  return {
    caseId: c.caseId,
    mode: c.mode,
    state: c.state,
    disposition: p?.disposition || c.disposition,
    catalogueEntry: str(p?.catalogueEntry),
    outcome: {
      state: c.state,
      disposition: c.disposition,
      receiver: c.receiver,
      mode: c.mode,
      writes: sent.length,
      verification: str(verified?.outcome) || undefined,
    },
    patient: patientLine(str(written?.ward), str(before), sent.length),
    result,
    writes: sent.length,
    verification: verified ? `${humanize(verified.outcome)}: ${verified.summary}` : '',
    dissent: dissent ? `${humanize(str(dissent.member))} said ${str(dissent.said)}` : '',
    planSummary: str(p?.summary),
    evidence,
  };
}

export interface EvidenceRow {
  label: string;
  rules: string;
  board: string;
  same: boolean;
}

const LABELS: [keyof EvidenceFacts, string][] = [
  ['failed', 'The failed delivery'],
  ['sameTime', 'Another movement at the same time'],
  ['receiver', 'The receiver when observed'],
  ['receipt', 'Receipt for the failed operation'],
  ['laterEvents', 'Later events'],
  ['takenAt', 'Evidence taken'],
  ['snapshotDigest', 'Snapshot digest'],
  ['materialDigest', 'Material digest'],
];

/** The two sides' evidence, fact by fact, and whether each fact reads the same. */
export function evidenceRows(rules: EvidenceFacts | null, board: EvidenceFacts | null): EvidenceRow[] {
  if (!rules || !board) return [];
  return LABELS.filter(([k]) => rules[k] || board[k]).map(([k, label]) => ({
    label,
    rules: k === 'takenAt' ? formatZoned(rules[k]) : rules[k],
    board: k === 'takenAt' ? formatZoned(board[k]) : board[k],
    same: rules[k] === board[k],
  }));
}

/**
 * How the evaluation scored one mode's play of a scenario (lib/proof.ts playedFor), as the compare strip marks it:
 * "Board: as expected", "Rules only: differs, wrote WARD-B", "Rules only: stopped by the gate, nothing written".
 * The tone is the evaluation result's: as expected positive, a wrong write or another outcome blocking, a stop by
 * the gate neutral. Null for a scenario the mode did not play.
 */
export function playedMark(
  who: 'board' | 'rules',
  result: PlayedResult | null | undefined,
  ward?: string,
): { label: string; tone: Tone } | null {
  const name = who === 'board' ? 'Board' : 'Rules only';
  switch (result) {
    case 'as-expected':
      return { label: `${name}: as expected`, tone: 'positive' };
    case 'wrote-wrongly':
      return { label: `${name}: differs, wrote ${ward || 'the receiver'}`, tone: 'blocking' };
    case 'stopped':
      return { label: `${name}: stopped by the gate, nothing written`, tone: 'neutral' };
    case 'differs':
      return { label: `${name}: differs`, tone: 'blocking' };
    default:
      return null;
  }
}
