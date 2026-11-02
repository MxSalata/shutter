import { Anchor, Button, Group, Stack, Text } from '@mantine/core';
import { IconChevronDown, IconHandStop, IconListDetails, IconSparkles } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import type { CaseDetail } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { ExpectedMark } from '@/components/ExpectedMark';
import { caseIrisLinks, IrisLinks } from '@/components/IrisLinks';
import { Meta } from '@/components/Meta';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PageHeader } from '@/components/PageHeader';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { caseOutcome, caseState, type ExpectedScenario, type OutcomeCase } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { useDetail } from '@/stores/appearance';
import { forwardedFrom } from './derive';
import { headerSentence } from './outcome';

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

/** How the case was investigated, as the cases list names it. */
const MODES: Record<string, string> = {
  rules: 'Rules only',
  single: 'One agent',
  board: 'Board',
  policy: 'Site policy',
};

/** The failure as the receiver answered it, "503 ward_unavailable", for the expert's line in Technical. */
function failureCode(c: CaseDetail): string {
  return [c.failureHttpStatus ? String(c.failureHttpStatus) : '', c.failureReasonCode ?? '']
    .filter(Boolean)
    .join(' ');
}

/**
 * The case's header: the cases' indigo mark and the title, then its status as one verdict and two facts (the outcome
 * first, then the workflow state where it says something the outcome does not, and the proposal); the plain sentence
 * of what failed; the case's line of facts; the IRIS row, always visible, with the case's message trace, workflow trace
 * and source message; and the rest of the record behind Details. In Technical the status adds
 * how the case compares with its scenario's expectation, and the line the failure's HTTP status and reason code.
 */
export function CaseHeader({
  c,
  provenance,
  actions,
  outcome,
  scenario,
  portalBase = '/csp/shutter/',
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
          <Group gap="xl" wrap="wrap" align="flex-start">
            <Meta label="What">
              {c.encounterId && c.encounterId !== '-'
                ? `${what}, encounter ${c.encounterId}`
                : `${what}, no encounter`}
            </Meta>
            {/* A case is one failed delivery to one receiver; one recorded before the server named it went to the bed manager */}
            <Meta label="Receiver">{c.receiver || 'Downstream Out'}</Meta>
            {source ? <Meta label="Source">{source}</Meta> : null}
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
            {technical && failure ? (
              <Meta label="Failure">
                <CodeChip>{failure}</CodeChip>
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
