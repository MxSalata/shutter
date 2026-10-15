import { Card, ScrollArea, Text, Timeline, Title } from '@mantine/core';
import type { CaseEvent } from '@/api/types';
import { STATE_COLOURS } from '@/components/StateBadge';
import { formatTime, humanize } from '@/lib/format';

const KIND_COLOURS: Record<string, string> = {
  artifact: 'indigo',
  note: 'gray',
  error: 'red',
  approval: 'grape',
  execution: 'teal',
};

export function CaseTimeline({ events }: { events: CaseEvent[] }) {
  return (
    <Card padding="md" component="section" aria-labelledby="timeline-title">
      <Title order={2} fz="lg" id="timeline-title" mb="sm">
        Timeline
      </Title>
      {events.length === 0 ? (
        <Text size="sm" c="dimmed">
          No events yet.
        </Text>
      ) : (
        <ScrollArea.Autosize mah="calc(100vh - 160px)" type="auto" offsetScrollbars>
          <Timeline bulletSize={12} lineWidth={2} active={events.length}>
            {events.map((e) => (
              <Timeline.Item
                key={e.seq}
                color={
                  e.kind === 'state' ? (STATE_COLOURS[e.toState] ?? 'gray') : (KIND_COLOURS[e.kind] ?? 'gray')
                }
                title={
                  <Text size="sm" fw={600}>
                    {e.kind === 'state'
                      ? humanize(e.toState)
                      : humanize(e.kind === 'artifact' ? 'record' : e.kind)}
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
        </ScrollArea.Autosize>
      )}
    </Card>
  );
}
