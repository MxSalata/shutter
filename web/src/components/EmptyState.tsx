import { Group, Stack, Text } from '@mantine/core';
import type { Icon } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { hueVar, type Hue } from '@/lib/hues';

/**
 * Nothing here yet, said once: the section's icon in its hue on a 40 px circle, one sentence (at most 15 words) and
 * one action. "No incidents yet. One opens when 5 deliveries to one receiver fail within 10 minutes." and "Site
 * profile".
 */
export function EmptyState({
  icon: I,
  hue = 'gray',
  children,
  action,
}: {
  icon: Icon;
  hue?: Hue;
  /** The sentence. */
  children: ReactNode;
  /** One link or button. */
  action?: ReactNode;
}) {
  return (
    <Group gap="md" wrap="nowrap" align="center" py="md">
      <span
        className="identity-mark"
        style={{ width: 40, height: 40, borderRadius: '50%', ['--mark-hue' as string]: hueVar(hue) }}
        aria-hidden
      >
        <I size={22} stroke={1.8} />
      </span>
      <Stack gap={4}>
        <Text size="md">{children}</Text>
        {action ? <div>{action}</div> : null}
      </Stack>
    </Group>
  );
}
