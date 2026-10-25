import { Badge, Group, Stack, Table, Text, Title, Tooltip } from '@mantine/core';
import { Timestamp } from '@/components/Timestamp';
import { displayZone, humanize } from '@/lib/format';
import { encounterTimeline } from './timeline';

const OUTCOMES: Record<string, string> = {
  applied: 'teal',
  already_committed: 'teal',
  unavailable: 'red',
  refused: 'red',
  error: 'red',
  uncertain: 'orange',
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
                  <Badge
                    size="sm"
                    variant="light"
                    color={OUTCOMES[r.outcome] ?? 'gray'}
                    style={{ textTransform: 'none' }}
                  >
                    {`${humanize(r.outcome) || 'Unknown'}${r.httpStatus ? ` (${r.httpStatus})` : ''}`}
                  </Badge>
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
                          color="orange"
                          variant="light"
                          tabIndex={0}
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
                          color="grape"
                          variant="light"
                          tabIndex={0}
                          style={{ textTransform: 'none' }}
                        >
                          Clock-change hour
                        </Badge>
                      </Tooltip>
                    ) : null}
                    {r.later ? (
                      <Badge size="sm" color="blue" variant="light" style={{ textTransform: 'none' }}>
                        Later event
                      </Badge>
                    ) : null}
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
