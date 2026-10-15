import { Stepper, Text } from '@mantine/core';
import { IconMinus, IconX } from '@tabler/icons-react';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { PHASES, phaseStatuses } from './derive';

export function Lifecycle({ c, events }: { c: CaseDetail; events: CaseEvent[] }) {
  const statuses = phaseStatuses(c.state, events);
  const firstOpen = statuses.findIndex((s) => s === 'current' || s === 'pending' || s === 'stopped');
  const active = firstOpen < 0 ? PHASES.length : firstOpen;
  return (
    <Stepper active={active} size="xs" mb="md" allowNextStepsSelect={false} aria-label="The case's progress">
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
  );
}
