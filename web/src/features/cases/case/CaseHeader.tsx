import { Anchor, Badge, Group, Stack, Text, Title, Tooltip } from '@mantine/core';
import { Link } from 'react-router';
import type { CaseDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { clampHeadline } from '@/lib/headline';

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

export function CaseHeader({ c }: { c: CaseDetail }) {
  const what = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
  const place = incidentPlace(c);
  return (
    <Stack gap="sm" mb="md">
      <Group gap="sm" wrap="wrap">
        <Title order={1}>Case {c.caseId}</Title>
        <StateBadge state={c.state} size="lg" />
        <DispositionBadge disposition={c.disposition} />
        {c.candidateEntry ? (
          <Tooltip
            label="No entry of the scenario catalogue fits this case, so it is flagged as a candidate for a new one"
            multiline
            maw={300}
          >
            <Badge color="violet" variant="light" tabIndex={0} style={{ textTransform: 'none' }}>
              New pattern
            </Badge>
          </Tooltip>
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
        {c.event === 'merge' ? (
          <Meta label="Merge">
            {`${c.priorPatientId || 'a prior record'}${c.priorPatientIdAuthority ? ` (${c.priorPatientIdAuthority})` : ''}${c.priorEncounterId ? `, visit ${c.priorEncounterId}` : ''} into ${c.patientId}${(c.mergeGroups ?? 1) > 1 ? `, and ${(c.mergeGroups ?? 1) - 1} more` : ''}`}
          </Meta>
        ) : null}
        <Meta label="Event time">
          <Timestamp iso={c.eventTime} />
        </Meta>
        <Meta label="Scenario and mode">{`${c.scenario || 'none'} · ${humanize(c.mode)}`}</Meta>
        <Meta label="Opened">
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
                <PortalLink href={c.links.visualTrace} what={`the Visual Trace of session ${c.ensSessionId}`}>
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
