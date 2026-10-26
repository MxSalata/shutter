import { Group, Text, type GroupProps } from '@mantine/core';
import type { Tone } from '@/lib/tone';
import { StatusBadge } from './StatusBadge';

/** What each of the five tones means, said once under a list of statuses. */
const MEANINGS: { tone: Tone; label: string; meaning: string }[] = [
  { tone: 'neutral', label: 'Neutral', meaning: 'a fact or a decision' },
  { tone: 'info', label: 'Information', meaning: 'running now, or worth seeing' },
  { tone: 'positive', label: 'Positive', meaning: 'a passed check or an effect verified at the receiver' },
  { tone: 'attention', label: 'Attention', meaning: 'a person is needed' },
  { tone: 'blocking', label: 'Blocking', meaning: 'refused or failed: nothing sent' },
];

export function ToneLegend(props: GroupProps) {
  return (
    <Group
      gap="md"
      wrap="wrap"
      component="ul"
      aria-label="What the colours mean"
      className="tone-legend"
      {...props}
    >
      {MEANINGS.map((m) => (
        <Group key={m.tone} gap={6} wrap="nowrap" component="li">
          <StatusBadge tone={m.tone} label={m.label} size="xs" />
          <Text size="xs" c="dimmed">
            {m.meaning}
          </Text>
        </Group>
      ))}
    </Group>
  );
}
