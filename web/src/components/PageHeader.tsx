import { Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';

export function PageHeader({
  title,
  subtitle,
  actions,
  tour,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  /** The guide's name for the page's introduction (`data-tour`). */
  tour?: string;
}) {
  return (
    <Group justify="space-between" align="flex-start" mb="md" wrap="wrap" gap="sm" data-tour={tour}>
      <Stack gap={4} style={{ minWidth: 0, flex: '1 1 320px' }}>
        <Title order={1}>{title}</Title>
        {subtitle ? (
          <Text c="dimmed" size="sm">
            {subtitle}
          </Text>
        ) : null}
      </Stack>
      {actions ? <Group gap="xs">{actions}</Group> : null}
    </Group>
  );
}
