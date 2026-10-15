import { Stack, Stepper, Text } from '@mantine/core';
import { IconMinus, IconX } from '@tabler/icons-react';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { PHASES, phaseStatuses, rounds } from './derive';

export function Lifecycle({ c, events }: { c: CaseDetail; events: CaseEvent[] }) {
  const statuses = phaseStatuses(c.state, events);
  const firstOpen = statuses.findIndex((s) => s === 'current' || s === 'pending' || s === 'stopped');
  const active = firstOpen < 0 ? PHASES.length : firstOpen;
  const round = rounds(events);
  return (
    <Stack gap={4} mb="md">
      {round > 1 ? (
        <Text size="sm" c="dimmed">
          Round {round}: the receiver changed after the approval, so the approval was void and the case was
          planned again on fresh evidence. The timeline keeps every round.
        </Text>
      ) : null}
      <Stepper active={active} size="xs" allowNextStepsSelect={false} aria-label="The case's progress">
        {PHASES.map((p, i) => {
          const s = statuses[i];
          return (
            <Stepper.Step
              key={p.key}
              label={p.label}
              description={
                <Text size="xs" c={s === 'stopped' ? 'red' : 'dimmed'}>
                  {s === 'stopped'
                    ? 'stopped here'
                    : s === 'skipped'
                      ? 'not needed'
                      : s === 'current'
                        ? 'now'
                        : ''}
                </Text>
              }
              color={s === 'stopped' ? 'red' : s === 'skipped' ? 'gray' : undefined}
              completedIcon={s === 'skipped' ? <IconMinus size={14} /> : undefined}
              icon={s === 'stopped' ? <IconX size={14} /> : undefined}
              loading={s === 'current'}
            />
          );
        })}
      </Stepper>
    </Stack>
  );
}
