import { Anchor, Badge, Group, Stack, Text, Title, Tooltip } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import type { CaseDetail } from '@/api/types';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';

function Meta({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <Stack gap={0}>
      <Text size="xs" c="dimmed">
        {label}
      </Text>
      {typeof children === 'string' ? <Text size="sm">{children}</Text> : children}
    </Stack>
  );
}

export function CaseHeader({ c }: { c: CaseDetail }) {
  const what = `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`;
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
          {c.headline}
        </Text>
      ) : null}
      <Group gap="xl" wrap="wrap" align="flex-start">
        <Meta label="What">{`${what}, encounter ${c.encounterId}`}</Meta>
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
        <Meta label="Case version">{String(c.version ?? '')}</Meta>
        <Meta label="Times">UTC, as the messages carry them</Meta>
        {c.links?.visualTrace || c.links?.workflowTrace ? (
          <Meta label="In the Management Portal">
            <Group gap="sm">
              {c.links.visualTrace ? (
                <Anchor href={c.links.visualTrace} target="_blank" rel="noreferrer" size="sm">
                  Message trace <IconExternalLink size={12} />
                </Anchor>
              ) : null}
              {c.links.workflowTrace ? (
                <Anchor href={c.links.workflowTrace} target="_blank" rel="noreferrer" size="sm">
                  Workflow trace <IconExternalLink size={12} />
                </Anchor>
              ) : null}
            </Group>
          </Meta>
        ) : null}
      </Group>
    </Stack>
  );
}
