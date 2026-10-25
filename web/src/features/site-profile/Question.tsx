import { Badge, Group, Text } from '@mantine/core';

/** Whether Shutter acts on an answer, or keeps it on record for the board and reviewers. */
export function Effect({ acts }: { acts: boolean }) {
  return (
    <Badge size="xs" variant="outline" color={acts ? 'blue' : 'gray'} style={{ textTransform: 'none' }}>
      {acts ? 'Changes what Shutter does' : 'On record: nothing reads it yet'}
    </Badge>
  );
}

export function Question({ n, text, acts }: { n: number; text: string; acts: boolean }) {
  return (
    <Group gap="xs" wrap="wrap">
      <Text fw={600} size="sm">
        {n}. {text}
      </Text>
      <Effect acts={acts} />
    </Group>
  );
}
