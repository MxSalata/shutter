import { Anchor, Button, Group, Stack, Text, Tooltip } from '@mantine/core';
import { IconChevronDown, IconHandStop, IconListDetails, IconSparkles } from '@tabler/icons-react';
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
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { HINT_EVENTS } from '@/theme';
import { caseOutcome, caseState, type ExpectedScenario, type OutcomeCase } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { useDetail } from '@/stores/appearance';
import { forwardedFrom } from './derive';
import { messageTypeLabel, messageTypeOf } from './message';
import { headerSentence } from './outcome';
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
 * The case's header: the cases' indigo mark and the title, then its status as one verdict and two facts (the outcome
 * first, then the workflow state where it says something the outcome does not, and the proposal); the plain sentence
 * of what failed; the case's line of facts; the IRIS row, always visible, with the case's message trace, workflow trace
 * and source message; and the rest of the record behind Details. In Technical the status adds
 * how the case compares with its scenario's expectation, and the line the message's type and trigger (MSH-9) and control
 * id, the item and the production it came in by, the receiver's class, the failure's kind, code and time, the source
 * message's header id (opening it in the Management Portal; the IRIS row links the session) and the plan's version,
 * digest and catalogue entry: each only when the server sent it, and nothing of the patient beyond the number Plain
 * shows.
 */
export function CaseHeader({
  c,
  provenance,
  actions,
  outcome,
  scenario,
  portalBase = '/csp/shutter/',
  snapshot,
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
}) {
  const technical = useDetail() === 'technical';
  const what = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
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
  // MSH-9 as the server read it from the message, else as the evidence recorded it
  const msh9 = c.messageType || message?.messageType || '';
  const entry = catalogueEntryOf(c);
  return (
    <PageHeader
      title={`Case ${c.caseId}`}
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
      lead={headerSentence(c)}
      meta={
        <Stack gap="sm" w="100%">
          <Group gap="lg" wrap="wrap" align="flex-start" style={{ rowGap: 'var(--mantine-spacing-sm)' }}>
            <Meta label="What">
              {c.encounterId && c.encounterId !== '-'
                ? `${what}, encounter ${c.encounterId}`
                : `${what}, no encounter`}
            </Meta>
            {/* The hospital number the message carries (PID-3), as the Evidence tab shows it: never a name or a birth date */}
            {c.patientId ? <Meta label="Patient">{c.patientId}</Meta> : null}
            {/* The message's HL7 type as IRIS parsed it ("2.5.1:ADT_A02"), from the evidence; in Technical, the version
                the message declares when the route parsed it as another */}
            {message || (technical && (msh9 || c.sourceMessageId)) ? (
              <Meta label="Message">
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
            {/* A case is one failed delivery to one receiver; one recorded before the server named it went to the bed manager */}
            {technical && c.receiverClass ? (
              <Meta label="Receiver">
                <Stack gap={0}>
                  <Text size="sm">{c.receiver || 'Downstream Out'}</Text>
                  <CodeChip fz="xs" data-testid="case-receiver-class">
                    {c.receiverClass}
                  </CodeChip>
                </Stack>
              </Meta>
            ) : (
              <Meta label="Receiver">{c.receiver || 'Downstream Out'}</Meta>
            )}
            {source ? <Meta label="Source">{source}</Meta> : null}
            {/* In Technical, the item and the production the feed's own message came in by; a forwarded case's source says
                both above */}
            {technical && !source && (c.sourceItem || c.production) ? (
              <Meta label="Source">
                <Group gap={4} wrap="wrap" data-testid="case-tech-source">
                  {c.sourceItem ? <Hinted hint="The item the message came in by">{c.sourceItem}</Hinted> : null}
                  {c.production ? <Hinted hint="The production it came in by">{c.production}</Hinted> : null}
                </Group>
              </Meta>
            ) : null}
            {c.event === 'merge' ? (
              <Meta label="Merge">
                {`${c.priorPatientId || 'a prior record'}${c.priorPatientIdAuthority ? ` (${c.priorPatientIdAuthority})` : ''}${c.priorEncounterId ? `, visit ${c.priorEncounterId}` : ''} into ${c.patientId}${(c.mergeGroups ?? 1) > 1 ? `, and ${(c.mergeGroups ?? 1) - 1} more` : ''}`}
              </Meta>
            ) : null}
            <Meta label="Scenario">{c.scenario || 'None'}</Meta>
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
