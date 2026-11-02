import { Group, Text, type GroupProps } from '@mantine/core';
import type { Tone } from '@/lib/tone';
import { StatusBadge } from './StatusBadge';

/**
 * What each of the five tones means, said once under a list of statuses, in one line where it fits. The only place an
 * xs badge belongs.
 */
export const TONE_MEANINGS: { tone: Tone; label: string; meaning: string }[] = [
  { tone: 'neutral', label: 'Neutral', meaning: 'closed, or a decision; nothing waiting' },
  { tone: 'info', label: 'Information', meaning: 'running now, or worth seeing' },
  {
    tone: 'positive',
    label: 'Positive',
    meaning: 'verified at the receiver, a passed check, or a result as expected',
  },
  { tone: 'attention', label: 'Attention', meaning: 'a person is needed' },
  { tone: 'blocking', label: 'Blocking', meaning: 'refused, failed or contradicted at the receiver' },
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
      {TONE_MEANINGS.map((m) => (
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
