import { Anchor, Button, Group, Stack, Text, Tooltip } from '@mantine/core';
import {
  IconChevronDown,
  IconHandStop,
  IconListDetails,
  IconSparkles,
  IconUserQuestion,
} from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import type { CaseDetail, Snapshot } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { ExpectedMark } from '@/components/ExpectedMark';
import { caseIrisLinks, IrisLinks } from '@/components/IrisLinks';
import { Meta } from '@/components/Meta';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PageHeader } from '@/components/PageHeader';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { asObject } from '@/lib/json';
import { HINT_EVENTS } from '@/theme';
import { caseOutcome, caseState, type ExpectedScenario, type OutcomeCase } from '@/lib/status';
import { toneText, type Status, type Tone } from '@/lib/tone';
import { useDetail } from '@/stores/appearance';
import { forwardedFrom, orderOrResult, outageResend } from './derive';
import { receiverWords } from './failureMapModel';
import { followedBoard } from './follows';
import { evidenceOf, messageTypeLabel, messageTypeOf } from './message';
import { actionHead, headerSentence } from './outcome';
import { FailedAt } from './TechFacts';
import { catalogueEntryOf, digestPrefix, failureCode, messageContentsLink } from './technical';

/** Where the case sits in its incident: the chain, its place in it and how the chain is released. */
function incidentPlace(c: CaseDetail): string {
  const i = c.incident;
  if (!i?.chain_seq) return '';
  const parts = [`chain ${i.chain_seq}, item ${i.position ?? ''}`];
  if (i.chain_kind) parts.push(humanize(i.chain_kind).toLowerCase());
  if (i.item_state) parts.push(humanize(i.item_state).toLowerCase());
  return parts.join(' · ');
}

/** Where a case another production forwarded came from, and Shutter's own copy of the message; empty otherwise. */
function sourceText(c: CaseDetail): string {
  const from = forwardedFrom({
    namespace: c.sourceNamespace,
    production: c.sourceProduction,
    route: c.sourceRoute,
    headerId: c.originHeaderId,
  });
  if (!from) return '';
  return `Forwarded from ${from}${c.sourceHeaderId ? `; Shutter's copy is message ${c.sourceHeaderId}` : ''}`;
}

/**
 * The header's sentence with the sending system's short name defined a click away (a dotted underline), rather than
 * spelt out in brackets: "The PAS transfer to WARD-B was not delivered: HTTP 503, ward_unavailable."
 */
function Lead({ c }: { c: CaseDetail }) {
  const sentence = headerSentence(c);
  const system = c.sourceSystem ?? '';
  const prefix = `The ${system} `;
  const term = system === 'PAS' ? 'pas' : system === 'BEDMGR' ? 'bedmgr' : undefined;
  if (!term || !sentence.startsWith(prefix)) return <>{sentence}</>;
  return (
    <>
      {'The '}
      <Term term={term}>{system}</Term>
      {` ${sentence.slice(prefix.length)}`}
    </>
  );
}

/**
 * The encounter as the receiver held it when Shutter looked, from the evidence: "WARD-C, bed BAY1-07", with its state
 * when that is not admitted. Empty when the evidence has no reading. It is the receiver's state before any write
 * Shutter made, so the header shows it only while nothing has been written.
 */
function receiverHolds(snapshot: Snapshot | null | undefined): string {
  const ward = evidenceOf(snapshot, 'ward_state');
  if (!ward || ward.not_applicable) return '';
  const status = Number(ward.http_status);
  if (status === 404) return 'No such encounter';
  if (status !== 200) return '';
  const b = asObject(ward.body) ?? {};
  const state = b.state ? String(b.state) : '';
  const place = [b.ward ? String(b.ward) : '', b.bed ? `bed ${String(b.bed)}` : '']
    .filter(Boolean)
    .join(', ');
  const parts = [state && state !== 'admitted' ? humanize(state) : '', place].filter(Boolean);
  return parts.join(', ');
}

/**
 * What Shutter wrote to the receiver, as the receipt counts it: "Nothing yet" while the case is still open. A message
 * resent through the engine with its receiver's outage says so: the receipt counts only the case's own writes.
 */
function writtenWords(oc: OutcomeCase, c: CaseDetail): string {
  const resent = outageResend(c);
  if (resent)
    return resent.closure === 'sent' ? 'Resent through the engine' : 'Resent; the receiver already held it';
  if (oc.writes === undefined || oc.writes === null) return '';
  const n = Number(oc.writes);
  if (n > 0) return `${n} write${n === 1 ? '' : 's'}`;
  return ['resolved', 'blocked', 'escalated', 'failed'].includes(oc.state) ? 'Nothing' : 'Nothing yet';
}

/** What has to happen next and who does it, for the line under the header's sentence: a person's step only. */
export interface HeaderNext {
  action: string;
  role: string;
  tone: Tone;
}

/** A code with what it is, or its whole value, in its tooltip: the header's Technical facts carry no label of their own. */
function Hinted({ hint, children }: { hint: string; children: string }) {
  return (
    <Tooltip label={hint} multiline maw={360} events={HINT_EVENTS}>
      <CodeChip fz="xs" tabIndex={0}>
        {children}
      </CodeChip>
    </Tooltip>
  );
}

/** How the case was investigated, as the cases list names it. */
const MODES: Record<string, string> = {
  rules: 'Rules only',
  single: 'One agent',
  board: 'Board',
  policy: 'Site policy',
};

/**
 * The case's header, read the way a busy reader on a ward or an integration engineer at 2 a.m. reads it: the case id
 * as a quiet label beside its status (one verdict and two facts: the outcome first, then the workflow state where it
 * says something the outcome does not, and the proposal); then the plain sentence of what failed, the largest text on
 * the page, its sending system defined a click away; a person's next step and who takes it; the patient's facts (what
 * Shutter wrote, the patient number, the encounter, the bed asked for, where the receiver had them); the message's
 * facts (its HL7 type, the receiver by name and production item, the event time); the IRIS row, always visible, with
 * the case's message trace, workflow trace and source message; and the rest of the record, the scenario included,
 * behind Details. In Technical the status adds how the case compares with its scenario's expectation, and the facts
 * the message's type and trigger (MSH-9) and control id, the item and the production it came in by, the receiver's
 * class, the failure's kind, code and time, the source message's header id (opening it in the Management Portal; the
 * IRIS row links the session) and the plan's version, digest and catalogue entry: each only when the server sent it,
 * and nothing of the patient beyond the number Plain shows.
 */
export function CaseHeader({
  c,
  provenance,
  actions,
  outcome,
  scenario,
  portalBase = '/csp/shutter/',
  snapshot,
  next,
}: {
  c: CaseDetail;
  provenance?: Status;
  /** Shown at the end of the title row: Convene the board, Ask about this case. */
  actions?: React.ReactNode;
  /** What the case wrote and what was verified, once read; the case's own fields until then. */
  outcome?: OutcomeCase;
  /** The case's scenario, for its expectation: rules alone's S8 write reads "Not as expected". */
  scenario?: ExpectedScenario | null;
  /** The Management Portal's base path, for the source message's link. */
  portalBase?: string;
  /** The case's evidence, once read: the message's HL7 type, as IRIS parsed it. */
  snapshot?: Snapshot | null;
  /** A person's next step, when the case waits for one: said under the sentence, before the facts. */
  next?: HeaderNext;
}) {
  const technical = useDetail() === 'technical';
  const place = incidentPlace(c);
  const source = sourceText(c);
  const oc: OutcomeCase = outcome ?? {
    state: c.state,
    disposition: c.disposition,
    receiver: c.receiver,
    mode: c.mode,
    writes: c.writes,
    verification: c.verification,
  };
  const verdict = caseOutcome(oc, scenario);
  const state = caseState(c.state);
  const [details, setDetails] = useState(false);
  const failure = failureCode(c);
  const iris = caseIrisLinks(c, portalBase);
  const message = messageTypeOf(snapshot);
  const written = writtenWords(oc, c);
  // Where the receiver had the patient, while Shutter has written nothing: after a write it would be out of date
  const holds = Number(oc.writes ?? 0) > 0 ? '' : receiverHolds(snapshot);
  // The receiver by what it is ("Bed-management system"), with the production item that carries it ("Downstream Out")
  const item = c.receiver || 'Downstream Out';
  const receiverName = receiverWords(String(evidenceOf(snapshot, 'route')?.receiver ?? '')).name;
  const nextHead = next ? actionHead(next.action).head : '';
  const nextKnown = !!next && !['Unknown', 'Not read yet'].includes(next.action);
  const roleKnown = !!next?.role && !['Unknown', 'Not read yet'].includes(next.role);
  // MSH-9 as the server read it from the message, else as the evidence recorded it
  const msh9 = c.messageType || message?.messageType || '';
  const entry = catalogueEntryOf(c);
  const board = followedBoard(c);
  return (
    <PageHeader
      title={`Case ${c.caseId}`}
      quiet
      icon={IconListDetails}
      hue="indigo"
      actions={actions}
      status={
        <>
          <OutcomeBadge c={oc} scenario={scenario} size="md" />
          {/* One verdict: the state only where it adds to the outcome (Resolved after Delivered, verified) */}
          {state.label !== verdict.short ? <StatusBadge {...state} size="xs" variant="outline" /> : null}
          {/* The state is shown once: an escalated case's proposal to escalate, or a case handled by hand or
              abandoned, would only repeat it */}
          {(c.state === 'escalated' && c.disposition === 'escalate') ||
          ['handled_by_hand', 'abandoned'].includes(c.disposition) ? null : (
            <DispositionBadge disposition={c.disposition} proposed />
          )}
          {technical && scenario ? <ExpectedMark c={oc} scenario={scenario} /> : null}
          {c.failureKind === 'unreadable' ? (
            <StatusBadge
              tone="attention"
              label="Held"
              hint="The site prevents failures: this message's HL7 schema is not loaded here, so Shutter held it and sent nothing"
              icon={IconHandStop}
            />
          ) : null}
          {c.candidateEntry ? (
            <StatusBadge
              tone="info"
              label="New pattern"
              hint="No entry of the scenario catalogue fits this case, so it is flagged as a candidate for a new one"
              icon={IconSparkles}
            />
          ) : null}
        </>
      }
      lead={<Lead c={c} />}
      meta={
        <Stack gap="sm" w="100%">
          {/* A person's next step and who takes it, said before the facts: the header's button goes to it */}
          {next && nextKnown ? (
            <Group gap={8} wrap="nowrap" align="flex-start" data-testid="case-next">
              <IconUserQuestion
                size={20}
                aria-hidden
                style={{ flex: 'none', color: toneText(next.tone), marginTop: 1 }}
              />
              <Text size="md">
                <Text span fw={700}>
                  {'Next: '}
                </Text>
                {nextHead}
                {roleKnown ? (
                  <Text span c="dimmed">
                    {` · ${next.role}`}
                  </Text>
                ) : null}
              </Text>
            </Group>
          ) : null}
          {/* The patient first: what Shutter wrote for them, their number, the encounter, the bed asked for and where
              the receiver had them */}
          <Group gap="lg" wrap="wrap" align="flex-start" style={{ rowGap: 'var(--mantine-spacing-sm)' }}>
            {written ? (
              <Meta label={<Term term="write">Shutter wrote</Term>}>
                <Text size="sm" fw={600} data-testid="case-written">
                  {written}
                </Text>
              </Meta>
            ) : null}
            {/* The hospital number the message carries (PID-3), as the Evidence tab shows it: never a name or a birth date */}
            {c.patientId ? (
              <Meta label={<Term term="patient-number">Patient</Term>}>
                <Text size="sm" fw={600}>
                  {c.patientId}
                </Text>
              </Meta>
            ) : null}
            <Meta label={<Term term="encounter">Encounter</Term>}>
              <Text size="sm" fw={600}>
                {c.encounterId && c.encounterId !== '-' ? c.encounterId : 'None'}
              </Text>
            </Meta>
            {/* An order or a result asks for no bed, whatever its PV1 carries */}
            {c.bed && !orderOrResult(c) ? <Meta label="Bed asked for">{c.bed}</Meta> : null}
            {holds ? (
              <Meta label="Receiver had">
                <Stack gap={0}>
                  <Text size="sm" data-testid="case-receiver-holds">
                    {holds}
                  </Text>
                  <Text size="xs" c="dimmed">
                    when Shutter looked
                  </Text>
                </Stack>
              </Meta>
            ) : null}
          </Group>
          {/* Then the message: its HL7 type, the receiver, when it happened, and the rest */}
          <Group gap="lg" wrap="wrap" align="flex-start" style={{ rowGap: 'var(--mantine-spacing-sm)' }}>
            {/* The message's HL7 type as IRIS parsed it ("2.5.1:ADT_A02"), from the evidence; in Technical, the version
                the message declares when the route parsed it as another, and MSH-9 and MSH-10 below */}
            {message || (technical && (msh9 || c.sourceMessageId)) ? (
              <Meta label={<Term term="adt">Message</Term>}>
                <Stack gap={0}>
                  {message ? (
                    <Text size="sm" className="mono-wrap" data-testid="case-message-type">
                      {messageTypeLabel(message)}
                    </Text>
                  ) : null}
                  {technical && message?.declaredOther ? (
                    <Text size="xs" c="dimmed">
                      {`The message says HL7 ${message.declaredOther}`}
                    </Text>
                  ) : null}
                  {/* In Technical, MSH-9's type and trigger and MSH-10's control id, each named in its tooltip */}
                  {technical && (msh9 || c.sourceMessageId) ? (
                    <Group gap={4} wrap="wrap" data-testid="case-tech-message">
                      {msh9 ? <Hinted hint="The message's type and trigger (MSH-9)">{msh9}</Hinted> : null}
                      {c.sourceMessageId ? (
                        <Hinted hint="The message control id (MSH-10)">{c.sourceMessageId}</Hinted>
                      ) : null}
                    </Group>
                  ) : null}
                </Stack>
              </Meta>
            ) : null}
            {/* A case is one failed delivery to one receiver; one recorded before the server named it went to the bed
                manager. Named as the failure map names it, with its production item under it; in Technical, the
                receiver's class too */}
            <Meta label={<Term term="receiver">Receiver</Term>}>
              {receiverName || (technical && c.receiverClass) ? (
                <Stack gap={0}>
                  {receiverName ? <Text size="sm">{receiverName}</Text> : null}
                  {receiverName ? (
                    <Text size="xs" c="dimmed" className="mono-wrap">
                      {item}
                    </Text>
                  ) : (
                    <Text size="sm">{item}</Text>
                  )}
                  {technical && c.receiverClass ? (
                    <CodeChip fz="xs" data-testid="case-receiver-class">
                      {c.receiverClass}
                    </CodeChip>
                  ) : null}
                </Stack>
              ) : (
                item
              )}
            </Meta>
            {source ? <Meta label="Source">{source}</Meta> : null}
            {/* In Technical, the item and the production the feed's own message came in by; a forwarded case's source says
                both above */}
            {technical && !source && (c.sourceItem || c.production) ? (
              <Meta label="Source">
                <Group gap={4} wrap="wrap" data-testid="case-tech-source">
                  {c.sourceItem ? (
                    <Hinted hint="The item the message came in by">{c.sourceItem}</Hinted>
                  ) : null}
                  {c.production ? <Hinted hint="The production it came in by">{c.production}</Hinted> : null}
                </Group>
              </Meta>
            ) : null}
            {c.event === 'merge' ? (
              <Meta label="Merge">
                {`${c.priorPatientId || 'a prior record'}${c.priorPatientIdAuthority ? ` (${c.priorPatientIdAuthority})` : ''}${c.priorEncounterId ? `, visit ${c.priorEncounterId}` : ''} into ${c.patientId}${(c.mergeGroups ?? 1) > 1 ? `, and ${(c.mergeGroups ?? 1) - 1} more` : ''}`}
              </Meta>
            ) : null}
            {c.incidentId ? (
              <Meta label="Incident">
                <Stack gap={0}>
                  <Anchor component={Link} to={`/incidents/${encodeURIComponent(c.incidentId)}`} size="sm">
                    {c.incidentId}
                  </Anchor>
                  {place ? (
                    <Text size="xs" c="dimmed">
                      {place}
                    </Text>
                  ) : null}
                </Stack>
              </Meta>
            ) : null}
            {board ? (
              <Meta label="Follows the board of">
                <Stack gap={0}>
                  <Anchor component={Link} to={`/cases/${encodeURIComponent(board.caseId)}`} size="sm">
                    {board.caseId}
                  </Anchor>
                  <Text size="xs" c="dimmed">
                    {board.note}
                  </Text>
                </Stack>
              </Meta>
            ) : null}
            <Meta label="Event time">
              <Timestamp iso={c.eventTime} />
            </Meta>
            {technical && (failure || c.failedAt) ? (
              <Meta label="Failure">
                <Stack gap={2} align="flex-start" data-testid="case-tech-failure">
                  <Group gap={4} wrap="wrap">
                    {failure ? <CodeChip>{failure}</CodeChip> : null}
                    {c.failureKind ? <CodeChip fz="xs">{c.failureKind}</CodeChip> : null}
                  </Group>
                  <FailedAt iso={c.failedAt} withDate />
                </Stack>
              </Meta>
            ) : null}
            {/* In Technical, the source message's header id, opening the message in the Management Portal (the trial's
                note there); the IRIS row below links the session's Visual Trace */}
            {technical && c.sourceHeaderId ? (
              <Meta label="Header">
                <Text size="sm" span data-testid="case-tech-header">
                  <PortalLink
                    href={messageContentsLink(portalBase, c.sourceHeaderId)}
                    what={`message ${c.sourceHeaderId}, the HL7 message whose delivery failed`}
                    quiet
                  >
                    {c.sourceHeaderId}
                  </PortalLink>
                </Text>
              </Meta>
            ) : null}
            {/* In Technical, the current plan: its version, the start of its digest and its catalogue entry */}
            {technical && (c.planVersion || c.planDigest || entry) ? (
              <Meta label="Plan">
                <Group gap={4} wrap="wrap" data-testid="case-tech-plan">
                  {c.planVersion ? <CodeChip fz="xs">{`v${c.planVersion}`}</CodeChip> : null}
                  {c.planDigest ? <Hinted hint={c.planDigest}>{digestPrefix(c.planDigest)}</Hinted> : null}
                  {entry ? <CodeChip fz="xs">{`catalogue ${entry}`}</CodeChip> : null}
                </Group>
              </Meta>
            ) : null}
            <Button
              variant="subtle"
              size="compact-sm"
              color="gray"
              onClick={() => setDetails((d) => !d)}
              aria-expanded={details}
              aria-controls="case-details"
              leftSection={
                <IconChevronDown
                  size={14}
                  aria-hidden
                  style={{
                    transform: details ? 'rotate(180deg)' : undefined,
                    transition: 'transform 150ms',
                  }}
                />
              }
              style={{ alignSelf: 'center' }}
            >
              Details
            </Button>
          </Group>
          {/* The production that carried the case, one quiet line in both modes: the expert's proof it ran in IRIS */}
          <IrisLinks links={iris} />
          {/* Who investigated, the record's times and version: kept a click away from the outcome */}
          {details ? (
            <Group id="case-details" gap="xl" wrap="wrap" align="flex-start">
              <Meta label="Scenario">{c.scenario || 'None'}</Meta>
              <Meta label="Investigated by">{MODES[c.mode] ?? humanize(c.mode)}</Meta>
              {provenance ? (
                <Meta label="Provenance">
                  <StatusBadge {...provenance} w="fit-content" />
                </Meta>
              ) : null}
              <Meta label="Case opened">
                <Timestamp iso={c.openedAt} />
              </Meta>
              {c.closedAt ? (
                <Meta label="Closed">
                  <Timestamp iso={c.closedAt} />
                </Meta>
              ) : null}
              <Meta label="Case version">{String(c.version ?? '')}</Meta>
              <Meta label="Times">{`In ${displayZone()}, as the PAS sends them; UTC in the tooltips`}</Meta>
            </Group>
          ) : (
            <div id="case-details" hidden />
          )}
        </Stack>
      }
    />
  );
}
