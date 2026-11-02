import { Group, Stack, Text } from '@mantine/core';
import { IconStack2 } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import type { IncidentDetail } from '@/api/types';
import { IdentityBadge } from '@/components/IdentityBadge';
import { IrisLinks, type IrisLink } from '@/components/IrisLinks';
import { Meta } from '@/components/Meta';
import { PageHeader } from '@/components/PageHeader';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { MODE_IDENTITY } from '@/lib/hues';
import { incidentOutcome } from '@/lib/status';
import { IncidentStateBadge } from '../badges';
import { incidentLead } from '../describe';

/** A fact in the header's line: its name, dimmed, then its value. */
function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Text size="sm" span>
      <Text span c="dimmed">
        {label}{' '}
      </Text>
      {children}
    </Text>
  );
}

const dot = (
  <Text size="sm" c="dimmed" span aria-hidden>
    ·
  </Text>
);

/** The incident's IRIS row: its workflow trace, when the incident carries one (F5). */
function irisLinks(inc: IncidentDetail): IrisLink[] {
  if (!inc.links?.workflowTrace || !inc.workflowSessionId) return [];
  return [
    {
      label: 'Workflow trace',
      number: inc.workflowSessionId,
      numberLabel: 'session',
      href: inc.links.workflowTrace,
      what: `the trace of the incident's workflow session ${inc.workflowSessionId}`,
    },
  ];
}

/**
 * The incident's header: the pink stack, "Incident I-000001" with its state and its outcome, the lead built from the
 * failures it holds, the receiver, the mode and the zone, the IRIS row, and the times and thresholds behind a
 * disclosure for the engineer.
 */
export function IncidentHeader({ inc }: { inc: IncidentDetail }) {
  const outcome = incidentOutcome(inc);
  const mode = MODE_IDENTITY[inc.mode];
  const threshold =
    inc.threshold && inc.windowMinutes ? `${inc.threshold} failures within ${inc.windowMinutes} minutes` : '';
  const stateWords = humanize(inc.state);
  return (
    <PageHeader
      title={`Incident ${inc.incidentId}`}
      icon={IconStack2}
      hue="pink"
      status={
        <Group gap="xs" wrap="wrap">
          <IncidentStateBadge state={inc.state} size="lg" />
          {outcome.label !== stateWords ? <StatusBadge {...outcome} size="lg" /> : null}
        </Group>
      }
      lead={incidentLead(inc)}
      meta={
        <Stack gap={6}>
          <Group gap={6} wrap="wrap" align="center">
            <Fact label="Receiver">{inc.receiver}</Fact>
            {dot}
            <Text size="sm" span c="dimmed">
              Mode
            </Text>
            <IdentityBadge hue={mode?.hue ?? 'gray'}>{mode?.label ?? humanize(inc.mode)}</IdentityBadge>
            {dot}
            <Fact label="Times in">{displayZone()}</Fact>
          </Group>
          <IrisLinks links={irisLinks(inc)} />
        </Stack>
      }
      detailsLabel="Opening, intake and closing"
      detailsKind="data"
      details={
        <Group gap="xl" wrap="wrap" align="flex-start">
          {threshold ? <Meta label="Opened at the threshold">{threshold}</Meta> : null}
          <Meta label="Opened">
            <Timestamp iso={inc.openedAt} />
          </Meta>
          {inc.intakeClosedAt ? (
            <Meta label="Intake closed">
              <Timestamp iso={inc.intakeClosedAt} />
            </Meta>
          ) : inc.quietSeconds ? (
            <Meta label="Intake">{`Closes after ${inc.quietSeconds} s with no new failure`}</Meta>
          ) : null}
          {inc.closedAt ? (
            <Meta label="Closed">
              <Timestamp iso={inc.closedAt} />
            </Meta>
          ) : null}
          <Meta label="Times">{`In ${displayZone()}, as the PAS sends them; UTC in the tooltips`}</Meta>
        </Group>
      }
    />
  );
}
