import { Stack, Text } from '@mantine/core';
import { NOT_CHECKED } from './receiver';

/** The first letter raised: the level's words are written to sit inside a sentence. */
const raised = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);

/**
 * What a case with no receipt says about its receiver: that nobody checked it, what its level allows when the engine
 * delivered the message, and, where nothing beside it shows the outcome, the outcome.
 */
export function NotCheckedWords({ outcome = '', accepted }: { outcome?: string; accepted: string }) {
  return (
    <Stack gap={4}>
      {outcome ? <Text size="sm">{raised(outcome)}</Text> : null}
      <Text size="sm" fw={600}>
        {NOT_CHECKED}
      </Text>
      {accepted ? (
        <Text size="sm" c="dimmed">
          {raised(accepted)}
        </Text>
      ) : null}
    </Stack>
  );
}
