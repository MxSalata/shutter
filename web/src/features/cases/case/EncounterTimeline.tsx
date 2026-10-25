import { Badge, Group, Stack, Table, Text, Title, Tooltip } from '@mantine/core';
import { IconAlertTriangle, IconClock } from '@tabler/icons-react';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import type { Tone } from '@/lib/tone';
import { displayZone, humanize } from '@/lib/format';
import { encounterTimeline } from './timeline';

/** What the receiver did with each operation: committed is a fact of its history, not a check, so information. */
const OUTCOMES: Record<string, Tone> = {
  applied: 'info',
  already_committed: 'info',
  unavailable: 'blocking',
  refused: 'blocking',
  error: 'blocking',
  uncertain: 'attention',
};

/**
 * The encounter's operations in event order, from the snapshot's timeline and the receiver's history: when each
 * happened, the order the feed sent them in, and the version each left at the receiver. Citations of `timeline`
 * land here.
 */
export function EncounterTimeline({ summary }: { summary: unknown }) {
  const rows = encounterTimeline(summary, displayZone());
  if (!rows.length) return null;
  return (
    <Stack gap={4} id="evidence-timeline" tabIndex={-1}>
      <Title order={3} fz="sm">
        Encounter timeline
      </Title>
      <Text size="xs" c="dimmed">
        Every operation for the encounter in event order, with the order the feed sent them in and the version
        each left at the downstream system.
      </Text>
      <Table.ScrollContainer minWidth={640}>
        <Table verticalSpacing={4} fz="sm">
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Event time</Table.Th>
              <Table.Th>Sent</Table.Th>
              <Table.Th>Operation</Table.Th>
              <Table.Th>Source</Table.Th>
              <Table.Th>Outcome</Table.Th>
              <Table.Th>Receiver version</Table.Th>
              <Table.Th>Flags</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {rows.map((r, i) => (
              <Table.Tr key={`${r.operationKey}-${i}`} fw={r.thisCase ? 600 : undefined}>
                <Table.Td>
                  <Timestamp iso={r.eventTime} />
                </Table.Td>
                <Table.Td>
                  {r.received !== null ? (
                    <Tooltip label={`Sent ${r.sentAt}`}>
                      <Text size="sm" tabIndex={0}>
                        {`#${r.received}`}
                      </Text>
                    </Tooltip>
                  ) : (
                    <Text size="sm" c="dimmed">
                      not by the feed
                    </Text>
                  )}
                </Table.Td>
                <Table.Td>
                  <Group gap={6} wrap="nowrap">
                    <Text size="sm" fw="inherit">
                      {`${humanize(r.event)}${r.ward ? ` to ${r.ward}` : ''}`}
                    </Text>
                    {r.thisCase ? (
                      <Badge size="xs" variant="filled" style={{ textTransform: 'none' }}>
                        This case
                      </Badge>
                    ) : null}
                  </Group>
                </Table.Td>
                <Table.Td>{`${r.system}${r.source === 'receiver' ? " (receiver's history)" : ''}`}</Table.Td>
                <Table.Td>
                  <StatusBadge
                    tone={OUTCOMES[r.outcome] ?? 'neutral'}
                    label={`${humanize(r.outcome) || 'Unknown'}${r.httpStatus ? ` (${r.httpStatus})` : ''}`}
                  />
                </Table.Td>
                <Table.Td>{r.versionAfter ? `v${r.versionAfter}` : 'none'}</Table.Td>
                <Table.Td>
                  <Group gap={4}>
                    {r.sameTime ? (
                      <Tooltip
                        label="Another operation for the encounter has the same event time, so which came first can't be told from the times"
                        multiline
                        maw={300}
                      >
                        <Badge
                          size="sm"
                          color="yellow"
                          variant="light"
                          tabIndex={0}
                          leftSection={<IconAlertTriangle size={12} aria-hidden />}
                          style={{ textTransform: 'none' }}
                        >
                          Same event time
                        </Badge>
                      </Tooltip>
                    ) : null}
                    {r.clockChange ? (
                      <Tooltip
                        label="The event time falls within the hour around a clock change in the feed's time zone: a local time there can happen twice, or not at all"
                        multiline
                        maw={300}
                      >
                        <Badge
                          size="sm"
                          color="yellow"
                          variant="light"
                          tabIndex={0}
                          leftSection={<IconClock size={12} aria-hidden />}
                          style={{ textTransform: 'none' }}
                        >
                          Clock-change hour
                        </Badge>
                      </Tooltip>
                    ) : null}
                    {r.later ? <StatusBadge tone="info" label="Later event" /> : null}
                  </Group>
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Stack>
  );
}
