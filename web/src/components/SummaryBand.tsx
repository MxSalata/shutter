import { SimpleGrid, Title, VisuallyHidden, type SimpleGridProps } from '@mantine/core';
import { useId, type ReactNode } from 'react';

/**
 * A row of stat tiles as a section, with a heading (visually hidden unless `showTitle`): count tiles take two columns
 * on a phone, three from a tablet and four from a wide screen; tiles with captions one, then three.
 */
export function SummaryBand({
  title,
  showTitle = false,
  cols = { base: 2, sm: 3, lg: 4 },
  children,
  tour,
}: {
  title: string;
  showTitle?: boolean;
  cols?: SimpleGridProps['cols'];
  children: ReactNode;
  tour?: string;
}) {
  const id = useId();
  return (
    <section aria-labelledby={id} data-tour={tour}>
      {showTitle ? (
        <Title order={2} id={id} mb="xs">
          {title}
        </Title>
      ) : (
        <VisuallyHidden id={id} component="h2">
          {title}
        </VisuallyHidden>
      )}
      <SimpleGrid cols={cols} spacing="sm" style={{ alignItems: 'start' }}>
        {children}
      </SimpleGrid>
    </section>
  );
}
