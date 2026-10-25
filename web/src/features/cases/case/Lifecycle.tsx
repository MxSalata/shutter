import { Stack, Stepper, Text } from '@mantine/core';
import {
  IconCheck,
  IconCircleDashed,
  IconMinus,
  IconProgress,
  IconUserQuestion,
  IconX,
} from '@tabler/icons-react';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { PHASES, phaseStatuses, type PhaseStatus } from './derive';

/**
 * The case's progress through the seven stages, one icon set with a word under each: done (a tick), now (in progress,
 * or a person's turn at the approval), not yet (a dashed circle), not needed (a dash), and where it stopped.
 */
export function Lifecycle({ c, events }: { c: CaseDetail; events: CaseEvent[] }) {
  const statuses = phaseStatuses(c.state, events);
  const firstOpen = statuses.findIndex((s) => s === 'current' || s === 'pending' || s === 'stopped');
  const active = firstOpen < 0 ? PHASES.length : firstOpen;
  // Where the case stopped: an escalation is a person's turn (attention), a block or a failure is red
  const handedOver = c.state === 'escalated';
  const stopColour = handedOver ? 'yellow' : 'red';
  const waiting = c.state === 'awaiting_approval';
  const words: Record<PhaseStatus, string> = {
    done: 'done',
    current: waiting ? 'waiting for approval' : 'in progress',
    pending: 'not yet',
    skipped: 'not needed',
    stopped: handedOver ? 'handed to a person here' : 'stopped here',
  };
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
                  {words[s]}
                </Text>
              }
              color={s === 'stopped' ? stopColour : s === 'skipped' ? 'gray' : undefined}
              completedIcon={
                s === 'skipped' ? <IconMinus size={14} aria-hidden /> : <IconCheck size={14} aria-hidden />
              }
              progressIcon={
                s === 'current' ? (
                  waiting ? (
                    <IconUserQuestion size={14} aria-hidden />
                  ) : (
                    <IconProgress size={14} aria-hidden />
                  )
                ) : undefined
              }
              icon={
                s === 'stopped' ? (
                  handedOver ? (
                    <IconUserQuestion size={14} aria-hidden />
                  ) : (
                    <IconX size={14} aria-hidden />
                  )
                ) : (
                  <IconCircleDashed size={14} aria-hidden />
                )
              }
            />
          );
        })}
      </Stepper>
      <Text size="xs" c="dimmed">
        Rehearsal is a dry run of the write at the receiver, rolled back; Approval is its release by a person,
        or the site&apos;s written policy.
      </Text>
    </Stack>
  );
}
