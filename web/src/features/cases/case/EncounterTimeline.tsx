import { Badge, Group, Table, Text, Tooltip } from '@mantine/core';
import { IconClock, IconClockExclamation } from '@tabler/icons-react';
import { StackTable } from '@/components/StackTable';
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
 * happened (with its date, and UTC beside it in Technical), the order the feed sent them in, and the version each left
 * at the receiver. Rows that share an event time say so, since their order can't be told from the times. The table
 * stacks on a phone, each cell under its column's name. The Evidence tab draws it as its operation timeline section,
 * where citations of `timeline` land.
 */
export function EncounterTimeline({ summary }: { summary: unknown }) {
  const rows = encounterTimeline(summary, displayZone());
  if (!rows.length) return null;
  return (
    <Table.ScrollContainer minWidth={640} className="stack-scroll">
      <StackTable verticalSpacing="xs" fz="sm" className="stack-table">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Event time</StackTable.Th>
            <StackTable.Th>Sent</StackTable.Th>
            <StackTable.Th>Operation</StackTable.Th>
            <StackTable.Th>Source</StackTable.Th>
            <StackTable.Th>Outcome</StackTable.Th>
            <StackTable.Th>Receiver version</StackTable.Th>
            <StackTable.Th>Flags</StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {rows.map((r, i) => (
            <StackTable.Tr key={`${r.operationKey}-${i}`} fw={r.thisCase ? 600 : undefined}>
              <StackTable.Td data-label="Event time">
                <Timestamp iso={r.eventTime} />
              </StackTable.Td>
              <StackTable.Td data-label="Sent">
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
              </StackTable.Td>
              <StackTable.Td data-label="Operation">
                <Group gap={6} wrap="wrap">
                  <Text size="sm" fw="inherit">
                    {`${humanize(r.event)}${r.ward ? ` to ${r.ward}` : ''}`}
                  </Text>
                  {r.thisCase ? (
                    <Badge size="sm" variant="filled" style={{ textTransform: 'none' }}>
                      This case
                    </Badge>
                  ) : null}
                </Group>
              </StackTable.Td>
              <StackTable.Td data-label="Source">
                {`${r.system}${r.source === 'receiver' ? " (receiver's history)" : ''}`}
              </StackTable.Td>
              <StackTable.Td data-label="Outcome">
                <StatusBadge
                  tone={OUTCOMES[r.outcome] ?? 'neutral'}
                  label={`${humanize(r.outcome) || 'Unknown'}${r.httpStatus ? ` (${r.httpStatus})` : ''}`}
                />
              </StackTable.Td>
              <StackTable.Td data-label="Receiver version">
                {r.versionAfter ? `v${r.versionAfter}` : 'none'}
              </StackTable.Td>
              <StackTable.Td data-label="Flags">
                <Group gap={4} wrap="wrap">
                  {r.sameTime ? (
                    <StatusBadge
                      tone="attention"
                      variant="outline"
                      label="Same event time"
                      hint="Another operation for the encounter has the same event time, so which came first can't be told from the times"
                      icon={IconClockExclamation}
                    />
                  ) : null}
                  {r.clockChange ? (
                    <StatusBadge
                      tone="attention"
                      variant="outline"
                      label="Clock-change hour"
                      hint="The event time falls within the hour around a clock change in the feed's time zone: a local time there can happen twice, or not at all"
                      icon={IconClock}
                    />
                  ) : null}
                  {r.later ? <StatusBadge tone="info" label="Later event" /> : null}
                </Group>
              </StackTable.Td>
            </StackTable.Tr>
          ))}
        </StackTable.Tbody>
      </StackTable>
    </Table.ScrollContainer>
  );
}
