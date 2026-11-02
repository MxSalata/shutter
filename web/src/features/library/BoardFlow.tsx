import { Group, SimpleGrid, Stack, Text } from '@mantine/core';
import { IconArrowDown, IconShieldCheck } from '@tabler/icons-react';
import type { ReactNode } from 'react';

/**
 * How a board works, in the order a reader meets it (and the page's DOM order): the specialists side by side (they
 * wrap, so a site's extra one is never dropped), the coordinator under them, then the gate. The arrows are decoration;
 * the caption says the same thing in words.
 */
export function BoardFlow({
  specialists,
  coordinators,
}: {
  specialists: ReactNode[];
  coordinators: ReactNode[];
}) {
  return (
    <Stack gap="sm">
      {specialists.length > 0 ? (
        <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md">
          {specialists}
        </SimpleGrid>
      ) : null}
      {specialists.length > 0 && coordinators.length > 0 ? <FlowArrow /> : null}
      {coordinators.length > 0 ? <Stack gap="md">{coordinators}</Stack> : null}
      {specialists.length + coordinators.length > 0 ? (
        <>
          <FlowArrow />
          <Group gap="xs" justify="center" align="flex-start" wrap="nowrap">
            <IconShieldCheck size={20} stroke={1.8} aria-hidden style={{ flex: 'none', marginTop: 1 }} />
            <Text size="sm">
              Then the gate checks the plan, and a person or the site's written policy releases it.
            </Text>
          </Group>
        </>
      ) : null}
    </Stack>
  );
}

/** One small arrow between two steps of the flow. */
function FlowArrow() {
  return (
    <Group justify="center" aria-hidden>
      <IconArrowDown size={20} stroke={1.6} style={{ color: 'var(--mantine-color-dimmed)' }} />
    </Group>
  );
}
