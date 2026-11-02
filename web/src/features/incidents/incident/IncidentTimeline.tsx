import { Card, ScrollArea, Stack, Text, Timeline, Title } from '@mantine/core';
import { useMemo } from 'react';
import type { IncidentEvent } from '@/api/types';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { formatTime } from '@/lib/format';
import { timelineLines, type TimelineLine } from '../describe';

const KIND_COLOURS: Record<string, string> = {
  state: 'blue',
  note: 'gray',
  release: 'blue',
  approval: 'blue',
};

/** A line's words; a line with more behind it is a disclosure that shows the events as the server wrote them. */
function Line({ line }: { line: TimelineLine }) {
  return (
    <Stack gap={0}>
      <Text size="xs" c="dimmed" component="div">
        <Timestamp iso={line.at} size="xs" c="dimmed" zone={false} />
        {line.actor ? ` · ${line.actor}` : ''}
      </Text>
      {line.opens ? (
        // The raw events are a log, not data to read through: they stay shut in both Detail levels
        <TechDetail label={line.label} kind="explain">
          <Stack gap={4}>
            {line.events.map((e, i) => (
              <Text key={i} size="xs">
                {formatTime(e.at)} {e.text}
              </Text>
            ))}
          </Stack>
        </TechDetail>
      ) : (
        <Text size="sm" fw={600}>
          {line.label}
        </Text>
      )}
    </Stack>
  );
}

/**
 * What happened, oldest first, each line with its date and time: runs of one kind collapse to a count ("6 cases
 * joined", "26 release steps") with the events behind it, so the story reads in a dozen lines, not fifty.
 */
export function IncidentTimeline({ events }: { events: IncidentEvent[] }) {
  const lines = useMemo(() => timelineLines(events), [events]);
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
          <Timeline bulletSize={12} lineWidth={2} active={lines.length}>
            {lines.map((line) => (
              <Timeline.Item
                key={line.key}
                color={KIND_COLOURS[line.events[0].kind] ?? 'gray'}
                title={<Line line={line} />}
              />
            ))}
          </Timeline>
        </ScrollArea.Autosize>
      )}
    </Card>
  );
}
