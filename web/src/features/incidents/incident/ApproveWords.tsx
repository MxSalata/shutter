import { Stack, Text } from '@mantine/core';
import { byEnv } from '@/env/copy';
import { plural } from '@/lib/format';

/**
 * What approving does, said before the checks (N18). On a live system it opens with the real consequence, "This sends
 * 2 fixes to Downstream Out, in this order, for real.", then the exact sentence the approval is bound to; in the trial
 * it invites, and says what you will see and that nothing leaves the browser.
 */
export function ApproveWords({ operations, receiver }: { operations: number; receiver: string }) {
  return byEnv({
    live: (
      <Stack gap={6}>
        <Text size="sm" fw={600}>
          This sends {plural(operations, 'fix', 'fixes')} to {receiver}, in this order, for real.
        </Text>
        <Text size="sm">
          {`You approve exactly this: resend these ${operations} operation${operations === 1 ? '' : 's'} to ${receiver}, in this order. Each one is rehearsed, gated and verified just before it goes, and goes at exactly the receiver version the one before it verified; a chain stops at the first surprise, and the rest comes back to a person. Each operation goes only under the catalogue entry and outcome listed for it; one whose fresh evidence reads differently stops its chain and comes back to a person.`}
        </Text>
      </Stack>
    ),
    trial: (
      <Text size="sm">
        Go ahead. You will see the recorded chain go out in order. Nothing leaves this browser.
      </Text>
    ),
  });
}
