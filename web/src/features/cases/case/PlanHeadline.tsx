import { Group, List, Stack, Text } from '@mantine/core';
import { keepTogether } from './keepTogether';
import type { PlanWords } from './planAction';

/** The overline over the headline and over its conditions, as the case's outcome cards carry theirs. */
function Kicker({ children }: { children: string }) {
  return (
    <Text size="xs" fw={700} tt="uppercase" c="dimmed" style={{ letterSpacing: '0.04em' }}>
      {children}
    </Text>
  );
}

/**
 * The plan's action as a headline, the largest words of its section: the action in the heavier weight, what it is
 * conditional on after it, and beside it (under it in a narrow column) the conditions as a short "only if" list. The
 * same block heads The plan, the Approval section and the review dialog, so the three can't say different things.
 */
export function PlanHeadline({ words }: { words: PlanWords }) {
  return (
    <Group className="plan-headline" align="flex-start" gap="md" wrap="wrap" data-testid="plan-headline">
      <Stack gap={4} style={{ flex: '1 1 320px', minWidth: 0 }}>
        <Kicker>{words.write ? 'Proposed action' : 'Proposed: no write'}</Kicker>
        <Text fz="lg" lh={1.4} data-testid="plan-action">
          <Text span inherit fw={700}>
            {keepTogether(words.action)}
          </Text>
          {keepTogether(words.condition ? `, ${words.condition}.` : '.')}
        </Text>
      </Stack>
      {words.onlyIf.length ? (
        <Stack gap={4} style={{ flex: '1 1 260px', minWidth: 0 }} data-testid="plan-only-if">
          <Kicker>Only if, when it is sent</Kicker>
          <List size="sm" spacing={2}>
            {words.onlyIf.map((x) => (
              <List.Item key={x}>{keepTogether(x)}</List.Item>
            ))}
          </List>
          <Text size="xs" c="dimmed">
            The receiver is read again and the gate checks both just before the write. Otherwise nothing is
            sent.
          </Text>
        </Stack>
      ) : null}
    </Group>
  );
}
