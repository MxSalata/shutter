import { Badge } from '@mantine/core';
import { IconTestPipe } from '@tabler/icons-react';

/**
 * "Trial" beside "Shutter" in the header of every trial page: filled grape, with the test-tube mark. It never shrinks,
 * since a squeezed badge cut its label to a sliver; below 360 px the label is visually hidden (styles.css) and the
 * mark stands alone, still named "Trial" for a screen reader.
 */
export function TrialPill() {
  return (
    <Badge
      className="trial-pill"
      variant="filled"
      size="sm"
      leftSection={<IconTestPipe size={12} aria-hidden />}
      style={{ textTransform: 'none', flexShrink: 0 }}
    >
      Trial
    </Badge>
  );
}
