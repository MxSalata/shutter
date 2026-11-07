import type { ReceiverCheck, ReceiverCheckField, SiteProfile } from '@/api/types';
import { manualCheckProblem } from '@/features/site-profile/profile';
import words from './receiver-check-words.json';

/**
 * The demo's stand-in for Shutter.Util.ReceiverCheck: the same rules and the same words (a test holds them equal), from
 * the recorded case. As on the server, each value is taken by name: nothing is copied from the snapshot whole.
 */
type Json = Record<string, unknown>;

export interface RecordedCase {
  detail: Json;
  snapshot?: { id?: unknown; summary?: Json } | null;
  blockedReason?: { code?: string } | null;
  plan?: { plan?: Json } | null;
  attempts?: unknown;
}

const str = (o: Json | undefined | null, k: string) =>
  o && o[k] !== undefined && o[k] !== null ? String(o[k]) : '';
const when = (iso: string) => (iso ? `${iso.slice(0, 19).replace('T', ' ')} UTC` : '');
const or = (v: string, otherwise: string) => v || otherwise;
const obj = (v: unknown) => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Json) : undefined);

function eventLine(c: Json) {
  const event = str(c, 'event');
  const time = str(c, 'eventTime');
  return lineOf(event, str(c, 'ward'), time, event === 'merge' ? c : undefined);
}

function lineOf(event: string, location: string, time: string, merge?: Json) {
  const at = time ? ` at ${time.slice(0, 16).replace('T', ' ')} UTC` : '';
  if (event === 'merge') {
    const prior = str(merge, 'priorPatientId');
    const authority = str(merge, 'priorPatientIdAuthority');
    const into = str(merge, 'patientId');
    const intoAuthority = str(merge, 'patientIdAuthority');
    return prior && into
      ? `Merge of ${prior}${authority ? ` (${authority})` : ''} into ${into}${intoAuthority ? ` (${intoAuthority})` : ''}${at}`
      : `Merge${at}`;
  }
  const cancel = event.startsWith('cancel_');
  const base = cancel ? event.slice(7) : event;
  const word =
    { admit: 'Admission', transfer: 'Transfer', discharge: 'Discharge', update: 'Update' }[base] ??
    'An event';
  const where = !location
    ? ''
    : base === 'discharge'
      ? ` from ${location}`
      : base === 'update'
        ? ` at ${location}`
        : ` to ${location}`;
  return cancel ? `Cancellation of the ${word.toLowerCase()}${where}${at}` : `${word}${where}${at}`;
}

function latestAttemptUncertain(r: RecordedCase) {
  const list = Array.isArray(r.attempts) ? r.attempts : (obj(r.attempts)?.items as unknown[] | undefined);
  const last = Array.isArray(list) ? obj(list.at(-1)) : undefined;
  return str(last, 'outcome') === 'uncertain';
}

function laterMovement(c: Json, s: Json) {
  const after = (h: Json) => {
    const key = str(h, 'operation_key');
    const t = str(h, 'event_time');
    return !!key && key !== str(c, 'operationKey') && !!t && t >= str(c, 'eventTime');
  };
  const line = (h: Json, source: string) => ({
    summary: `${lineOf(str(h, 'event'), str(h, 'ward'), str(h, 'event_time'))}${str(h, 'bed') ? `, bed ${str(h, 'bed')}` : ''}.`,
    source,
  });
  const history = (obj(s.ward_state)?.history as Json[] | undefined) ?? [];
  const seen = history.filter(after).at(-1);
  if (seen) return line(seen, "the receiver's history");
  const timeline = (s.timeline as Json[] | undefined) ?? [];
  const sent = timeline.filter((h) => str(h, 'outcome') === 'applied' && after(h)).at(-1);
  if (sent) return line(sent, "Shutter's record of messages");
  if (Number(s.later_events) > 0)
    return { summary: words.later_known, source: "Shutter's record of messages" };
  return null;
}

const notModelled = (c: Json) => {
  const text = str(c, 'failureText');
  return text.startsWith('This message is ') && text.split(':')[0]!.includes(', not ADT');
};

function variantOf(r: RecordedCase, s: Json): keyof typeof words.variants {
  const c = r.detail;
  const kind = str(c, 'failureKind');
  const event = str(c, 'event');
  if (kind === 'withheld') return 'withheld';
  if (event === 'T02') return 'document';
  if (event === 'R01') return 'result';
  if (notModelled(c)) return 'other_message';
  if (latestAttemptUncertain(r)) return 'uncertain';
  const reason = r.blockedReason?.code ?? '';
  const receipt = obj(s.receipt);
  const hasReceipt =
    !!receipt &&
    Number(s.receipt_http_status) === 200 &&
    str(receipt, 'operation_key') === str(c, 'operationKey');
  if (hasReceipt || reason === 'ALREADY_COMMITTED') return 'already_applied';
  if (kind === 'uncertain_outcome' || reason === 'WRITE_OUTCOME_UNKNOWN') return 'uncertain';
  const entry = str(obj(s.catalogue), 'entry');
  if (
    ['unmappable', 'unreadable'].includes(kind) ||
    ['E11', 'E12', 'E13', 'E18'].includes(entry) ||
    [
      'PARSE_FAILED',
      'SCHEMA_UNKNOWN',
      'UNMAPPABLE',
      'UNKNOWN_ENCOUNTER',
      'NO_ENCOUNTER',
      'PATIENT_MISMATCH',
      'EVENT_TIME_IMPLAUSIBLE',
    ].includes(reason)
  )
    return 'identity_or_time';
  if (
    kind === 'rejected' ||
    obj(s.bed_conflict) ||
    ['BED_OCCUPIED', 'OCCUPANT_CASE_FAILED', 'WAITING_FOR_OCCUPANT_CASE'].includes(reason)
  )
    return 'refusal';
  const plan = obj(obj(r.plan?.plan)?.plan);
  if (obj(plan?.correction_steps)) return 'history_correction';
  return laterMovement(c, s) ? 'later_movement' : 'manual_compare';
}

export function receiverCheckFor(r: RecordedCase, profile: SiteProfile): ReceiverCheck {
  const c = r.detail;
  const s = r.snapshot?.summary ?? {};
  const variant = variantOf(r, s);
  const vw = words.variants[variant] as (typeof words.variants)['manual_compare'] & { note?: string };
  const state = obj(s.ward_state);
  const encounter = str(c, 'encounterId');
  const read =
    !!state &&
    Number(s.ward_state_http_status) === 200 &&
    !!str(state, 'state') &&
    str(state, 'encounter_id') === encounter;
  const at = when(str(s, 'observed_at'));
  const receiver = str(c, 'receiver');
  const entry = profile.receivers?.find((x) => x.name === receiver);
  const noDoc = !['document', 'result', 'other_message'].includes(variant);
  const noApi = !!entry && !entry.api && !!entry.features;
  const doubtfulTime =
    variant === 'identity_or_time' &&
    (str(obj(s.catalogue), 'entry') === 'E13' || r.blockedReason?.code === 'EVENT_TIME_IMPLAUSIBLE');
  const unsure =
    ['unmappable', 'unreadable'].includes(str(c, 'failureKind')) || r.blockedReason?.code === 'PARSE_FAILED';
  const row = (label: string, value: string, source: 'message' | 'doubtful'): ReceiverCheckField =>
    value ? { label, value, source } : { label, value: words.missing, source: 'unavailable' };
  const event = str(c, 'event');
  const fields: ReceiverCheckField[] = [];
  if (['admit', 'transfer', 'update', 'cancel_transfer', 'cancel_admit'].includes(event)) {
    fields.push(row('Ward', str(c, 'ward'), unsure ? 'doubtful' : 'message'));
    fields.push(row('Bed', str(c, 'bed'), unsure ? 'doubtful' : 'message'));
  }
  fields.push(
    row('Effective time', when(str(c, 'eventTime')), unsure || doubtfulTime ? 'doubtful' : 'message'),
  );
  let summary = `${eventLine(c)}.`;
  if (variant === 'refusal')
    summary += ` ${str(c, 'failureReasonCode') === 'bed_occupied' || obj(s.bed_conflict) ? words.bed_occupied : words.refused}`;
  if (variant === 'uncertain') summary += ` ${words.attempted}`;
  const runbook = entry?.manual_check;
  const showRunbook = !!runbook?.runbook && !manualCheckProblem(runbook);
  const later = laterMovement(c, s);
  return {
    caseId: str(c, 'caseId'),
    caseVersion: Number(c.version),
    snapshotId: str(r.snapshot as Json | undefined, 'id'),
    profileVersion: Number(profile.version ?? 0),
    guideVersion: words.version,
    guideDigest: 'sha256:recorded',
    variant,
    receiverEvidence: noDoc && read ? 'read' : 'unavailable',
    evidenceNote: !noDoc
      ? words.evidence.documents
      : read
        ? words.evidence.read.replace('{at}', at)
        : noApi
          ? words.evidence.no_api
          : words.evidence.unreadable,
    receiverRead:
      noDoc && read
        ? { at, state: str(state, 'state'), ward: str(state, 'ward'), bed: str(state, 'bed') }
        : null,
    identity: {
      patientId: or(str(c, 'patientId'), words.missing),
      authority: or(str(c, 'patientIdAuthority'), words.missing),
      encounterId: !encounter || encounter === '-' ? words.no_encounter : encounter,
      receiver: or(receiver, words.missing),
      sourceSystem: or(str(c, 'sourceSystem'), words.missing),
      messageType: or(str(obj(s.message), 'message_type'), words.missing),
      controlId: or(str(c, 'sourceMessageId'), words.missing),
      timeLabel: 'Event time',
      time: or(when(str(c, 'eventTime')), words.missing),
      messageRef: or(str(c, 'sourceHeaderId'), words.missing),
      sourceRoute: or(str(c, 'sourceRoute'), words.missing),
      collectedAt: or(at, words.missing),
    },
    messageRequest: {
      kind: event,
      summary,
      note: vw.note ?? (variant === 'withheld' ? '' : words.asked_note),
      fields,
    },
    laterMovement: variant === 'later_movement' || variant === 'history_correction' ? later : null,
    queueWarning: words.queue,
    checks: [
      {
        id: variant,
        where: vw.where,
        compare: vw.compare,
        meanings: (['present', 'absent', 'different', 'cannot_tell'] as const).map((answer) => ({
          answer,
          label: vw.meanings[answer][0]!,
          text: vw.meanings[answer][1]!,
        })),
      },
    ],
    siteRunbook: showRunbook ? runbook.runbook! : null,
    unknown: [...(doubtfulTime ? [words.time_doubtful] : []), ...vw.unknown],
    limitations: [],
    report: words.report,
  };
}
