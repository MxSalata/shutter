import { Card, Stack, Text, Timeline, Title } from '@mantine/core';
import type { CaseEvent } from '@/api/types';
import { stateColour } from '@/components/StateBadge';
import { formatTime, humanize } from '@/lib/format';
import { eventRounds } from './derive';

/** Events other than a state change: neutral records and notes, information for a release or a write, red for an error. */
const KIND_COLOURS: Record<string, string> = {
  artifact: 'gray',
  note: 'gray',
  error: 'red',
  approval: 'blue',
  execution: 'blue',
};

function RoundTimeline({ events }: { events: CaseEvent[] }) {
  return (
    <Timeline bulletSize={12} lineWidth={2} active={events.length}>
      {events.map((e) => (
        <Timeline.Item
          key={e.seq}
          color={e.kind === 'state' ? stateColour(e.toState) : (KIND_COLOURS[e.kind] ?? 'gray')}
          title={
            <Text size="sm" fw={600}>
              {e.kind === 'state' ? humanize(e.toState) : humanize(e.kind === 'artifact' ? 'record' : e.kind)}
            </Text>
          }
        >
          <Text size="xs" c="dimmed">
            {formatTime(e.at)}
            {e.actor && e.actor !== 'system' ? ` · ${e.actor}` : ''}
          </Text>
          <Text size="sm">{e.text}</Text>
        </Timeline.Item>
      ))}
    </Timeline>
  );
}

/** The case's timeline in timestamp order, grouped by round with the current round first. */
export function CaseTimeline({ events }: { events: CaseEvent[] }) {
  const rounds = eventRounds(events);
  return (
    <Card padding="md" component="section" aria-labelledby="timeline-title">
      <Title order={2} fz="lg" id="timeline-title" mb="sm">
        Timeline
      </Title>
      {events.length === 0 ? (
        <Text size="sm" c="dimmed">
          No events yet.
        </Text>
      ) : rounds.length === 1 ? (
        <RoundTimeline events={events} />
      ) : (
        <Stack gap="lg">
          <Text size="sm" c="dimmed">
            {`${rounds.length} rounds: the receiver or the evidence changed, and the case was planned again. The current round comes first; the earlier ones are kept as they happened.`}
          </Text>
          {rounds
            .map((r, i) => ({ r, n: i + 1 }))
            .reverse()
            .map(({ r, n }) => (
              <Stack key={n} gap="xs" component="section" aria-labelledby={`round-${n}-title`}>
                <Title order={3} fz="md" id={`round-${n}-title`}>
                  {n === rounds.length ? `Round ${n}, current` : `Round ${n}`}
                </Title>
                <RoundTimeline events={r} />
              </Stack>
            ))}
        </Stack>
      )}
    </Card>
  );
}
