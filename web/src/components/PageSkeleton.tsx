import { Center, Group, Loader, SimpleGrid, Skeleton, Stack, Text, VisuallyHidden } from '@mantine/core';

/** The page layouts a loading page can sketch. */
export type SkeletonShape = 'header-tiles-table' | 'header-cards' | 'detail';

/**
 * A page while its data loads: with a `shape`, grey blocks in the page's own layout (a header, then tiles and a table,
 * cards, or a detail page's band and sections), with the loading words for screen readers; without one, the spinner
 * and the words, as before. Either way it is the page's one `status` region, which goes when the data arrives.
 */
export function PageSkeleton({ label = 'Loading…', shape }: { label?: string; shape?: SkeletonShape }) {
  if (!shape)
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
  return (
    <Stack gap="lg" role="status" aria-live="polite" data-shape={shape}>
      <VisuallyHidden>{label}</VisuallyHidden>
      <Stack gap={8} aria-hidden>
        <Group gap="sm">
          <Skeleton height={36} width={36} radius="md" />
          <Skeleton height={30} width="40%" radius="sm" />
        </Group>
        <Skeleton height={16} width="60%" radius="sm" />
      </Stack>
      {shape === 'header-tiles-table' ? (
        <Stack gap="lg" aria-hidden>
          <SimpleGrid cols={{ base: 2, sm: 3, lg: 4 }} spacing="sm">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} height={96} radius="md" />
            ))}
          </SimpleGrid>
          <Stack gap={6}>
            {[0, 1, 2, 3, 4, 5].map((i) => (
              <Skeleton key={i} height={28} radius="sm" />
            ))}
          </Stack>
        </Stack>
      ) : shape === 'header-cards' ? (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="sm" aria-hidden>
          {[0, 1, 2, 3, 4, 5].map((i) => (
            <Skeleton key={i} height={140} radius="md" />
          ))}
        </SimpleGrid>
      ) : (
        <Stack gap="md" aria-hidden>
          <Skeleton height={120} radius="md" />
          <Skeleton height={220} radius="md" />
          <Skeleton height={160} radius="md" />
        </Stack>
      )}
    </Stack>
  );
}
