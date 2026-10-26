import type { Escalation, SiteProfile } from '@/api/types';

/**
 * The demo's stand-in for Shutter.Util.EscalationDraft: the same sections, from the recorded case. The recorded answers
 * carry no date of birth (it is read from the original message inside IRIS), so the demo's draft leaves it out.
 */
type Json = Record<string, unknown>;
const str = (o: Json | undefined, k: string) =>
  o && o[k] !== undefined && o[k] !== null ? String(o[k]) : '';

function eventLine(event: string, location: string, time: string) {
  const word =
    { admit: 'Admission', transfer: 'Transfer', discharge: 'Discharge', update: 'Update' }[event] ??
    'An event';
  const where = !location
    ? ''
    : event === 'discharge'
      ? ` from ${location}`
      : event === 'update'
        ? ` at ${location}`
        : ` to ${location}`;
  return `${word}${where}${time ? ` at ${time.slice(0, 16).replace('T', ' ')} UTC` : ''}`;
}

export function teamFor(profile: SiteProfile | undefined, receiver: string, teamId?: string) {
  const teams = profile?.teams ?? [];
  if (teamId) return teams.find((t) => t.id === teamId);
  return (
    teams.find((t) => t.receivers?.includes(receiver)) ??
    teams[0] ?? { id: '', name: profile?.approvers?.escalation ?? '', mailbox: '' }
  );
}

export function draftEscalation(
  recorded: {
    detail: Json;
    snapshot?: Json | null;
    blockedReason?: Json | null;
    attempts?: unknown;
    plan?: Json | null;
  },
  team: { id?: string; name?: string; mailbox?: string; cc?: string[] },
  seq: number,
  user: string,
): Escalation {
  const c = recorded.detail;
  const receiver = str(c, 'receiver') || 'the downstream system';
  const items = (recorded.snapshot?.items as Json[] | undefined) ?? [];
  const state = (items.find((i) => i.kind === 'ward_state')?.data as Json | undefined)?.body as
    Json | undefined;
  const reason = recorded.blockedReason ?? undefined;
  const catalogue = reason?.catalogue as Json | undefined;
  // A receiver that keeps the history of record: the plan carries the correcting steps for its team (CONTRACTS 10)
  const inner = ((recorded.plan?.plan as Json | undefined)?.plan ?? undefined) as Json | undefined;
  const correction = inner?.correction_steps as Json | undefined;
  const steps = Array.isArray(correction?.steps) ? (correction.steps as string[]) : [];
  const missing = (correction?.missing as Json | undefined) ?? {};
  const correcting = steps.length
    ? [
        'CORRECTING THE HISTORY',
        `  the ${str(missing, 'event')}${str(missing, 'ward') ? ` to ${str(missing, 'ward')}` : ''} at ${str(missing, 'event_time')} is missing from the history ${str(correction, 'receiver')} keeps; ${steps.length} steps for its team are on the plan.`,
        ...steps.map((step, i) => `  ${i + 1}. ${step}`),
        '',
      ]
    : [];
  const lines = [
    `To ${team.name || 'the team'},`,
    '',
    `Shutter could not safely recover a failed message to ${receiver}. Please compare the systems and correct them by hand; Shutter has sent nothing more for this message.`,
    '',
    'PATIENT',
    `  Hospital number: ${str(c, 'patientId')}${str(c, 'patientIdAuthority') ? ` (${str(c, 'patientIdAuthority')})` : ''}`,
    `  Encounter (visit number): ${str(c, 'encounterId')}`,
    '',
    'THE EVENT',
    `  ${eventLine(str(c, 'event'), str(c, 'ward'), str(c, 'eventTime'))}`,
    `  Source system: ${str(c, 'sourceSystem')}, message control id ${str(c, 'sourceMessageId')}`,
    `  Operation key: ${str(c, 'operationKey')}`,
    '',
    'WHAT FAILED',
    `  ${str(c, 'failureText') || str(c, 'failureKind')}`,
    '',
    'WHY SHUTTER STOPPED',
    catalogue
      ? `  ${str(catalogue, 'title')} (${str(reason, 'code')})\n  ${str(catalogue, 'text')}\n  Next action: ${str(catalogue, 'nextAction')}`
      : `  The case is ${str(c, 'state')}: ${str(c, 'headline')}`,
    '',
    ...correcting,
    `WHAT ${receiver.toUpperCase()} HOLDS`,
    state
      ? [
          `  ${str(state, 'state').replace(/^./, (x) => x.toUpperCase())} in ${str(state, 'ward')}, version ${str(state, 'version')}`,
          ...((state.history as Json[] | undefined) ?? []).map(
            (h) => `  - ${eventLine(str(h, 'event'), str(h, 'ward'), str(h, 'event_time'))}`,
          ),
        ].join('\n')
      : '  Not known: the receiver’s record could not be read.',
    '',
    'WHAT SHUTTER SENT',
    Array.isArray(recorded.attempts) && recorded.attempts.length
      ? `  ${recorded.attempts.length} write(s); see the case.`
      : '  Nothing: Shutter sent no write for this case.',
    '',
    'WHEN IT IS CORRECTED',
    `  Reply to this email with what was changed, or record it on the case, then choose Reinvestigate on the case page: Shutter reads ${receiver} again and verifies the correction.`,
    '',
    'REFERENCES',
    `  Case: ${str(c, 'caseId')}`,
    '',
    'This email was drafted by Shutter from its record of the case and reviewed by the person who sent it.',
  ];
  const body = lines.join('\n');
  const subject = `Shutter ${str(c, 'caseId')}: manual check needed, ${receiver}, encounter ${str(c, 'encounterId')}`;
  return {
    caseId: str(c, 'caseId'),
    seq,
    state: 'draft',
    teamId: team.id ?? '',
    teamName: team.name ?? '',
    to: team.mailbox ?? '',
    cc: (team.cc ?? []).join(', '),
    subject,
    body,
    bodyDigest: digest(team.mailbox ?? '', (team.cc ?? []).join(', '), subject, body),
    draftedBy: user,
    draftedAt: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
  };
}

/** Not the server's SHA-256: in the demo the digest only has to change when the text does. */
export function digest(...parts: string[]) {
  let h = 5381;
  for (const ch of parts.join('\n')) h = ((h * 33) ^ ch.charCodeAt(0)) >>> 0;
  return `demo:${h.toString(16)}`;
}
