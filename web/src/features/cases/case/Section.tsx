import { Card, Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';

/** One step of the case's story: a card with a heading, an optional note under it and a badge on the right. */
export function Section({
  id,
  title,
  note,
  aside,
  children,
}: {
  id: string;
  title: ReactNode;
  note?: ReactNode;
  aside?: ReactNode;
  children: ReactNode;
}) {
  return (
    <Card padding="md" id={id} component="section" aria-labelledby={`${id}-title`}>
      <Stack gap="sm">
        <Group justify="space-between" align="flex-start" wrap="wrap" gap="xs">
          <Stack gap={2} style={{ minWidth: 0, flex: '1 1 260px' }}>
            <Title order={2} fz="lg" id={`${id}-title`}>
              {title}
            </Title>
            {note ? (
              <Text size="sm" c="dimmed">
                {note}
              </Text>
            ) : null}
          </Stack>
          {aside ? <Group gap={6}>{aside}</Group> : null}
        </Group>
        {children}
      </Stack>
    </Card>
  );
}

/** What a section shows before its step has happened. */
export function NotYet({ children }: { children: ReactNode }) {
  return (
    <Text size="sm" c="dimmed" fs="italic">
      {children}
    </Text>
  );
}
