import { Group, Stack, Text, Title } from '@mantine/core';
import type { IncidentDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { Meta } from '@/components/Meta';
import { IncidentStateBadge } from '../badges';

export function IncidentHeader({ inc }: { inc: IncidentDetail }) {
  const threshold =
    inc.threshold && inc.windowMinutes ? `${inc.threshold} failures within ${inc.windowMinutes} minutes` : '';
  return (
    <Stack gap="sm" mb="md">
      <Group gap="sm" wrap="wrap">
        <Title order={1}>Incident {inc.incidentId}</Title>
        <IncidentStateBadge state={inc.state} size="lg" />
      </Group>
      {inc.summary ? (
        <Text size="md" fw={500}>
          {inc.summary}
        </Text>
      ) : null}
      <Group gap="xl" wrap="wrap" align="flex-start">
        <Meta label="Receiver">{inc.receiver}</Meta>
        {threshold ? <Meta label="Opened at the threshold">{threshold}</Meta> : null}
        <Meta label="Mode">{humanize(inc.mode)}</Meta>
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
        {inc.links?.workflowTrace && inc.workflowSessionId ? (
          <Meta label="In the Management Portal">
            <PortalLink
              href={inc.links.workflowTrace}
              what={`the trace of the incident's workflow session ${inc.workflowSessionId}`}
            >
              Workflow trace
            </PortalLink>
          </Meta>
        ) : null}
      </Group>
    </Stack>
  );
}
