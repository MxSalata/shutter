import { Group, Text } from '@mantine/core';
import { CHECK_STATES, checkCounts, checkState } from '@/lib/status';

/**
 * The gate's checks at a glance: one 10 px square per check in its tone (passed green, not applicable grey, blocked
 * or unknown red), then the words that say it all ("10 passed, 1 not applicable"). The squares are decoration.
 */
export function CheckStrip({ checks }: { checks: { result: string; reason_code?: string }[] }) {
  if (!checks.length) return null;
  return (
    <Group gap={8} wrap="wrap" align="center" className="check-strip-row">
      <span className="check-strip" aria-hidden>
        {checks.map((c, i) => (
          <span key={i} data-tone={CHECK_STATES[checkState(c)].tone} />
        ))}
      </span>
      <Text size="sm" span>
        {checkCounts(checks)}
      </Text>
    </Group>
  );
}
