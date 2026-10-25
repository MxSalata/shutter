import { Anchor, Group, Stack, Text, Title } from '@mantine/core';
import { IconSparkles } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { CaseDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { clampHeadline } from '@/lib/headline';
import { traceScreenshot } from '@/lib/screenshots';
import type { Status } from '@/lib/tone';
import { forwardedFrom } from './derive';

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

export function CaseHeader({ c, provenance }: { c: CaseDetail; provenance?: Status }) {
  const what = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
  const place = incidentPlace(c);
  const source = sourceText(c);
  return (
    <Stack gap="sm" mb="md">
      <Group gap="sm" wrap="wrap">
        <Title order={1}>Case {c.caseId}</Title>
        <StateBadge state={c.state} size="lg" />
        <DispositionBadge disposition={c.disposition} />
        {c.candidateEntry ? (
          <StatusBadge
            tone="info"
            label="New pattern"
            hint="No entry of the scenario catalogue fits this case, so it is flagged as a candidate for a new one"
            icon={IconSparkles}
          />
        ) : null}
      </Group>
      {c.headline ? (
        <Text size="md" fw={500}>
          {clampHeadline(c.headline)}
        </Text>
      ) : null}
      <Group gap="xl" wrap="wrap" align="flex-start">
        <Meta label="What">
          {c.encounterId && c.encounterId !== '-'
            ? `${what}, encounter ${c.encounterId}`
            : `${what}, no encounter`}
        </Meta>
        {source ? <Meta label="Source">{source}</Meta> : null}
        {c.event === 'merge' ? (
          <Meta label="Merge">
            {`${c.priorPatientId || 'a prior record'}${c.priorPatientIdAuthority ? ` (${c.priorPatientIdAuthority})` : ''}${c.priorEncounterId ? `, visit ${c.priorEncounterId}` : ''} into ${c.patientId}${(c.mergeGroups ?? 1) > 1 ? `, and ${(c.mergeGroups ?? 1) - 1} more` : ''}`}
          </Meta>
        ) : null}
        <Meta label="Scenario">{c.scenario || 'None'}</Meta>
        <Meta label="Investigated by">{MODES[c.mode] ?? humanize(c.mode)}</Meta>
        {provenance ? (
          <Meta label="Provenance">
            <StatusBadge {...provenance} w="fit-content" />
          </Meta>
        ) : null}
        <Meta label="Event time">
          <Timestamp iso={c.eventTime} />
        </Meta>
        <Meta label="Case opened">
          <Timestamp iso={c.openedAt} />
        </Meta>
        {c.closedAt ? (
          <Meta label="Closed">
            <Timestamp iso={c.closedAt} />
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
    </Stack>
  );
}
