import type { CorrectionDraftView, CorrectionSequence } from '@/api/types';

/** A drawn sequence for one later movement, in the shape of S22 on a profile whose receiver takes cancels (CONTRACTS 10). */
export const DRAWN_SEQUENCE: CorrectionSequence = {
  drawn: true,
  reason_code: '',
  reason: '',
  k: 1,
  count: 3,
  receiver_version: 3,
  observed_at: '2026-10-16T09:50:00Z',
  cancels_flag: true,
  resend_timestamp: 'original',
  steps: [
    {
      n: 1,
      kind: 'cancel',
      trigger: 'A12',
      cancels: {
        event: 'transfer',
        ward: 'WARD-C',
        event_time: '2026-10-16T09:45:00Z',
        operation_key: 'ENC-1022|transfer|WARD-C|2026-10-16T09:45:00Z',
        source_message_id: 'MSG02203',
        ens_header_id: '203',
      },
      after: { by_source: 'WARD-B', by_receiver: 'WARD-A' },
    },
    {
      n: 2,
      kind: 'replay',
      trigger: 'A02',
      event: 'transfer',
      ward: 'WARD-B',
      event_time: '2026-10-16T09:20:00Z',
      operation_key: 'ENC-1022|transfer|WARD-B|2026-10-16T09:20:00Z',
      source_message_id: 'MSG02202',
      ens_header_id: '202',
      body_digest: 'sha256:1111111111111111111111111111111111111111111111111111111111111111',
      non_ascii: false,
      after: { by_source: 'WARD-B', by_receiver: 'WARD-B' },
    },
    {
      n: 3,
      kind: 'replay',
      trigger: 'A02',
      event: 'transfer',
      ward: 'WARD-C',
      event_time: '2026-10-16T09:45:00Z',
      operation_key: 'ENC-1022|transfer|WARD-C|2026-10-16T09:45:00Z',
      source_message_id: 'MSG02203',
      ens_header_id: '203',
      body_digest: 'sha256:2222222222222222222222222222222222222222222222222222222222222222',
      non_ascii: false,
      after: { by_source: 'WARD-C', by_receiver: 'WARD-C' },
    },
  ],
  left_alone: [],
  end: { ward: 'WARD-C', history: ['WARD-A', 'WARD-B', 'WARD-C'] },
  checked_at: '2026-10-16T10:00:00Z',
};

/** The seed's answer for S22: the receiver takes no cancels, so nothing is drawn. */
export const CANCELS_FALSE: CorrectionSequence = {
  drawn: false,
  reason_code: 'cancels_false',
  reason:
    "No sequence: the receiver's entry says it takes no cancels (cancels: false), so the cancel-and-replay route isn't available here; its own records procedure is the route.",
  k: 0,
  count: 0,
  steps: [],
  left_alone: [],
};

const PID = 'PID|1||MRN1022^^^HOSP^MR~9991002200^^^NHS^NH||SYNTH^VERA||19700202|F';
const seg = (...lines: string[]) => `${lines.join('\r')}\r`;

export const CANCEL_TEXT = seg(
  'MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|[SENDER: time sent]||ADT^A12^ADT_A12|[SENDER: new control id]|P|2.5.1',
  'EVN|A12|[SENDER: time recorded]||||[SITE: event time for a cancel]',
  PID,
  'PV1|1|I|WARD-B^BAY2^04^HOSP|||WARD-C^BAY1^07^HOSP|||||||||||||ENC-1022|||||||||||||||||||||||||20261016100000',
);
export const REPLAY_B_TEXT = seg(
  'MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|20261016102000||ADT^A02^ADT_A02|MSG02202|P|2.5.1',
  'EVN|A02|20261016102000||||20261016102000',
  PID,
  'PV1|1|I|WARD-B^BAY2^04^HOSP|||WARD-A^BAY1^02^HOSP|||||||||||||ENC-1022|||||||||||||||||||||||||20261016100000',
);
export const REPLAY_C_TEXT = seg(
  'MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|20261016104500||ADT^A02^ADT_A02|MSG02203|P|2.5.1',
  'EVN|A02|20261016104500||||20261016104500',
  PID,
  'PV1|1|I|WARD-C^BAY1^07^HOSP|||WARD-B^BAY2^04^HOSP|||||||||||||ENC-1022|||||||||||||||||||||||||20261016100000',
);

/** The route's answer for the sequence above: nine header lines, three messages, ten things it can't know. */
export const DRAWN_DRAFT: CorrectionDraftView = {
  caseId: 'C-000055',
  drawn: true,
  reason_code: '',
  reason: '',
  header: [
    'Draft. Shutter has sent none of this and will send none of it.',
    'Drawn from the snapshot taken at 2026-10-16T09:50:00Z with Records Out at version 3. If the version has moved, throw this away and reinvestigate.',
    'Approval: step 4 above. Who approved, and when, goes on the case.',
    'Send to Records Out only, straight to its own interface: never through the inbound service or the router, or every other receiver on the feed gets these too.',
    "Before the first message, and again before each one: check Records Out's own screen for this patient, and reload this case. A change made by hand at the receiver is invisible to Shutter, and this block is redrawn on every read.",
    'Pause the feed to Records Out first. In a stock production that means stopping the whole operation item, so every other message for that receiver queues while this runs; a new movement for this patient in the middle breaks the sequence.',
    'While this runs the receiver shows the wrong place 2 times: after message 1: by the source WARD-B, by what this receiver holds WARD-A; after message 2: by the source WARD-B, by what this receiver holds WARD-B.',
    'If the receiver stops at any step, go forward from where it stopped, as the states above say. Never try to reverse a cancel.',
    'Message text is read on this page by an approver, and each read is recorded on the case. The email for this case carries none of it.',
  ],
  messages: [
    {
      n: 1,
      kind: 'cancel',
      trigger: 'A12',
      label: "New: cancels the transfer to WARD-C at 20261016104500. Shutter's table, not a source message.",
      text: CANCEL_TEXT,
      withheld: '',
      after: 'After it, by the source: WARD-B. By what this receiver holds: WARD-A.',
      body_digest: '',
    },
    {
      n: 2,
      kind: 'replay',
      trigger: 'A02',
      label:
        'Replay, unchanged: control id MSG02202, event 20261016102000, transfer to WARD-B. Digest of the stored text sha256:1111111111111111111111111111111111111111111111111111111111111111.',
      text: REPLAY_B_TEXT,
      withheld: '',
      after: 'After it, by the source: WARD-B. By what this receiver holds: WARD-B.',
      body_digest: 'sha256:1111111111111111111111111111111111111111111111111111111111111111',
    },
    {
      n: 3,
      kind: 'replay',
      trigger: 'A02',
      label:
        'Replay, unchanged: control id MSG02203, event 20261016104500, transfer to WARD-C. Digest of the stored text sha256:2222222222222222222222222222222222222222222222222222222222222222.',
      text: REPLAY_C_TEXT,
      withheld: '',
      after: 'After it, by the source: WARD-C. By what this receiver holds: WARD-C.',
      body_digest: 'sha256:2222222222222222222222222222222222222222222222222222222222222222',
    },
  ],
  cannot_know: [
    {
      what: 'Whether the receiver takes cancels',
      why: 'Taking cancels is a profile answer, here true; the profile can be wrong.',
      does: 'Shows the flag.',
    },
    {
      what: 'The right PV1-3 for the cancel',
      why: 'The receiver never held WARD-B, so one that checks the prior location may refuse or disagree.',
      does: "Shows both: WARD-B by the source, WARD-A by what this receiver holds. The source's is used, because HL7 has PV1-3 show the location before the original transfer.",
    },
    {
      what: 'Duplicate handling',
      why: 'A receiver may refuse a replayed control id or operation key as already seen.',
      does: "Names it. A new control id would be a person's edit at send, never Shutter's.",
    },
    {
      what: 'Fresh timestamps',
      why: "The profile's resend_timestamp says whether the receiver needs a fresh MSH-7; here it says original.",
      does: "Shows the flag. If fresh, a person changes it at send, and the digest then won't match.",
    },
    {
      what: 'What hangs off the later movement',
      why: "A cancel deletes it; notes, charges or orders attached there are the receiver's business.",
      does: "Names the question for the receiver's team.",
    },
    {
      what: 'Whether the beds are still free',
      why: 'A bed in this history may hold someone now; a bed taken stops the sequence half way.',
      does: 'Says check before starting.',
    },
    {
      what: 'Who else is fed by this receiver',
      why: 'Its subscribers see the patient move back and forward.',
      does: 'Names it.',
    },
    {
      what: 'Whether anything newer has happened',
      why: 'A draft is a reading at one moment.',
      does: 'The version line, and the redraw on every read.',
    },
    {
      what: 'A change made by hand at the receiver',
      why: "It is invisible over HL7, and a message on a route the index doesn't cover is invisible too.",
      does: "The line about checking the receiver's own screen.",
    },
    {
      what: "What the source's time meant",
      why: "Operation keys are in UTC, and the source's own text may be in local time.",
      does: "Shows the source's own text, never a converted time.",
    },
  ],
  left_alone: [],
  never: [
    'Never edit a value in a source message or show one as edited.',
    'Never guess a time, control id or location.',
    "Never treat one cancel as enough when there is more than one later movement, or send a cancel against a movement that isn't current at that step.",
    'Never use Z99, an A08 as a location fix, or a resend of the original on its own.',
    "Never put message text in the plan, the email or any agent's context.",
    'Never call this verified: the case is closed by hand, as step 8 says.',
  ],
  digest: 'sha256:3333333333333333333333333333333333333333333333333333333333333333',
  checked_at: '2026-10-16T10:05:00Z',
};

/** The same read after a new admission on another visit number: nothing is drawn, and no text comes. */
export const STOPPED_DRAFT: CorrectionDraftView = {
  caseId: 'C-000055',
  drawn: false,
  reason_code: 'further_message',
  reason:
    'No sequence: a further message for this patient was found: admit on encounter ENC-2044 at 2026-10-16T11:00:00Z (header 240), after the movements this draft covers. A person reads it first.',
  header: [],
  messages: [],
  cannot_know: [],
  left_alone: [],
  never: [],
  digest: '',
  checked_at: '2026-10-16T11:05:00Z',
};
