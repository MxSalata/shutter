import { Stack, Stepper, Text } from '@mantine/core';
import { IconMinus, IconUserQuestion, IconX } from '@tabler/icons-react';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { PHASES, phaseStatuses } from './derive';

export function Lifecycle({ c, events }: { c: CaseDetail; events: CaseEvent[] }) {
  const statuses = phaseStatuses(c.state, events);
  const firstOpen = statuses.findIndex((s) => s === 'current' || s === 'pending' || s === 'stopped');
  const active = firstOpen < 0 ? PHASES.length : firstOpen;
  // Where the case stopped: an escalation is a person's turn (attention), a block or a failure is red
  const handedOver = c.state === 'escalated';
  const stopColour = handedOver ? 'yellow' : 'red';
  return (
    <Stack gap={4} mb="md">
      <Stepper active={active} size="xs" allowNextStepsSelect={false} aria-label="The case's progress">
        {PHASES.map((p, i) => {
          const s = statuses[i];
          return (
            <Stepper.Step
              key={p.key}
              label={p.label}
              description={
                <Text size="xs" c={s === 'stopped' ? stopColour : 'dimmed'}>
                  {s === 'stopped'
                    ? handedOver
                      ? 'handed to a person here'
                      : 'stopped here'
                    : s === 'skipped'
                      ? 'not needed'
                      : s === 'current'
                        ? 'now'
                        : ''}
                </Text>
              }
              color={s === 'stopped' ? stopColour : s === 'skipped' ? 'gray' : undefined}
              completedIcon={s === 'skipped' ? <IconMinus size={14} /> : undefined}
              icon={
                s === 'stopped' ? (
                  handedOver ? (
                    <IconUserQuestion size={14} aria-hidden />
                  ) : (
                    <IconX size={14} aria-hidden />
                  )
                ) : undefined
              }
              loading={s === 'current'}
            />
          );
        })}
      </Stepper>
    </Stack>
  );
}
