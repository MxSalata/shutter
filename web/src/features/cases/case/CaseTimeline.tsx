import { Card, ScrollArea, Text, Timeline, Title } from '@mantine/core';
import type { CaseEvent } from '@/api/types';
import { stateColour } from '@/components/StateBadge';
import { formatTime, humanize } from '@/lib/format';

/** Events other than a state change: neutral records and notes, information for a release or a write, red for an error. */
const KIND_COLOURS: Record<string, string> = {
  artifact: 'gray',
  note: 'gray',
  error: 'red',
  approval: 'blue',
  execution: 'blue',
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
        <ScrollArea.Autosize
          mah="calc(100vh - 160px)"
          type="auto"
          offsetScrollbars
          // A region that scrolls must take the keyboard's focus, so the keys can scroll it
          viewportProps={{ tabIndex: 0, role: 'region', 'aria-label': 'Timeline events' }}
        >
          <Timeline bulletSize={12} lineWidth={2} active={events.length}>
            {events.map((e) => (
              <Timeline.Item
                key={e.seq}
                color={e.kind === 'state' ? stateColour(e.toState) : (KIND_COLOURS[e.kind] ?? 'gray')}
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
