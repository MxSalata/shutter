import { Center, Loader, Stack, Text } from '@mantine/core';

export function PageSkeleton({ label = 'Loading…' }: { label?: string }) {
  return (
    <Center py={80} role="status" aria-live="polite">
      <Stack align="center" gap="xs">
        <Loader size="sm" />
        <Text size="sm" c="dimmed">
          {label}
        </Text>
      </Stack>
    </Center>
  );
}
