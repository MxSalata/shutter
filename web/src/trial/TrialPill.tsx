import { Badge } from '@mantine/core';
import { IconTestPipe } from '@tabler/icons-react';

/** "Trial" beside "Shutter" in the header of every trial page: filled grape, with the test-tube mark. */
export function TrialPill() {
  return (
    <Badge
      className="trial-pill"
      variant="filled"
      size="sm"
      leftSection={<IconTestPipe size={12} aria-hidden />}
      style={{ textTransform: 'none' }}
    >
      Trial
    </Badge>
  );
}
