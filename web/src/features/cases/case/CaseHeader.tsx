import { Anchor, Button, Group, Stack, Text, Title } from '@mantine/core';
import { IconChevronDown, IconHandStop, IconSparkles } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import type { CaseDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { traceScreenshot } from '@/lib/screenshots';
import type { Status } from '@/lib/tone';
import { forwardedFrom } from './derive';
import { headerSentence } from './outcome';

/** A labelled fact in a page header. */
export function Meta({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <Stack gap={0}>
      <Text size="xs" c="dimmed">
        {label}
      </Text>
      {typeof children === 'string' ? <Text size="sm">{children}</Text> : children}
    </Stack>
  );
}

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

export function CaseHeader({
  c,
  provenance,
  actions,
}: {
  c: CaseDetail;
  provenance?: Status;
  /** Shown at the end of the title row: Ask about this case. */
  actions?: React.ReactNode;
}) {
  const what = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
  const place = incidentPlace(c);
  const source = sourceText(c);
  const [details, setDetails] = useState(false);
  return (
    <Stack gap="sm" mb="md">
      <Group gap="sm" wrap="wrap">
        <Title order={1}>Case {c.caseId}</Title>
        <StateBadge state={c.state} size="lg" />
        {/* The state is shown once: an escalated case's proposal to escalate would only repeat it */}
        {c.state === 'escalated' && c.disposition === 'escalate' ? null : (
          <DispositionBadge disposition={c.disposition} proposed />
        )}
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
        {actions ? <Group ml="auto">{actions}</Group> : null}
      </Group>
      <Text size="md" fw={500} maw="90ch">
        {headerSentence(c)}
      </Text>
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
              style={{ transform: details ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
            />
          }
          style={{ alignSelf: 'center' }}
        >
          Details
        </Button>
      </Group>
      {/* Who investigated, the record's times and version, and the portal: kept a click away from the outcome */}
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
          {c.links?.visualTrace || c.links?.workflowTrace ? (
            <Meta label="In the Management Portal">
              <Group gap="sm">
                {c.links.visualTrace ? (
                  <PortalLink
                    href={c.links.visualTrace}
                    what={`the Visual Trace of session ${c.ensSessionId}`}
                    screenshot={traceScreenshot(c)}
                  >
                    Message trace
                  </PortalLink>
                ) : null}
                {c.links.workflowTrace ? (
                  <PortalLink
                    href={c.links.workflowTrace}
                    what={`the trace of the case's workflow session ${c.workflowSessionId}`}
                  >
                    Workflow trace
                  </PortalLink>
                ) : null}
              </Group>
            </Meta>
          ) : null}
        </Group>
      ) : (
        <div id="case-details" hidden />
      )}
    </Stack>
  );
}
