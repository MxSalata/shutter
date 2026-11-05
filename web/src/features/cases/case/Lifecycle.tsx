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
import { TechDetail } from '@/components/TechDetail';
import { PHASES, phaseStatuses, type PhaseStatus } from './derive';

/** The stages the trial's replay fills in after a reader's approval: Approval, Dispatch and Verification. */
export const REPLAYED_STAGES = 3;

/** A stage of the strip, by its key: evidence, investigation, gate, rehearsal, approval, dispatch, verification. */
export type StageKey = (typeof PHASES)[number]['key'];

/** What pressing a reached stage shows, in its accessible name: "Evidence: done, show the evidence". */
const SHOWS: Record<StageKey, string> = {
  evidence: 'the evidence',
  investigation: 'the investigation',
  gate: 'the plan and the gate',
  rehearsal: 'the rehearsal',
  approval: 'the approval',
  dispatch: 'the dispatch',
  verification: 'the verification',
};

/**
 * The case's progress through the seven stages, one icon set with a word under each: done (a tick), now (in progress,
 * or a person's turn at the approval), not yet (a dashed circle), not needed (a dash), and where it stopped, in the
 * blocking tone (an escalation is a person's turn, in attention). The last stage is drawn positive once the verifier
 * found the effect at the receiver. During the trial's replay after an approval, `reveal` marks the last three stages
 * (`data-revealed`), which fill in one at a time.
 *
 * With `onStage`, each stage the case has reached (done, now, stopped or not needed) is a button that takes the reader
 * to where the page tells that stage (the Evidence tab, the board, a story step), named for it ("Evidence: done, show
 * the evidence"); a stage not reached yet stays plain text.
 */
export function Lifecycle({
  c,
  events,
  verified = false,
  reveal,
  onStage,
  investigation,
}: {
  c: CaseDetail;
  events: CaseEvent[];
  /** The verifier found the effect at the receiver. */
  verified?: boolean;
  /** The replay's marks for the last three stages, by their place among them (0 to 2). */
  reveal?: (i: number) => { 'data-revealed': 'true' | 'false' };
  /** Shows where the page tells a reached stage. */
  onStage?: (stage: StageKey) => void;
  /** What the investigation stage shows, when not the investigation itself: "the board". */
  investigation?: string;
}) {
  const statuses = phaseStatuses(c.state, events);
  const firstOpen = statuses.findIndex((s) => s === 'current' || s === 'pending' || s === 'stopped');
  const active = firstOpen < 0 ? PHASES.length : firstOpen;
  // Where the case stopped: an escalation is a person's turn (attention), a block or a failure is red
  const handedOver = c.state === 'escalated';
  const stopColour = handedOver ? 'yellow' : 'red';
  const waiting = c.state === 'awaiting_approval';
  // "Not yet" would promise a stage a stopped case won't reach unless a person sends it on
  const halted = ['blocked', 'escalated', 'failed'].includes(c.state);
  const words: Record<PhaseStatus, string> = {
    done: 'done',
    current: waiting ? 'waiting for approval' : 'in progress',
    pending: halted ? 'not reached' : 'not yet',
    skipped: 'not needed',
    stopped: handedOver ? 'handed to a person here' : 'stopped here',
  };
  return (
    <Stack
      gap={4}
      mb="md"
      id="case-lifecycle"
      style={{ scrollMarginTop: 'calc(var(--shutter-header-h) + 16px)' }}
    >
      <Stepper
        active={active}
        size="xs"
        allowNextStepsSelect={false}
        aria-label="The case's progress"
        onStepClick={onStage ? (i) => onStage(PHASES[i].key) : undefined}
      >
        {PHASES.map((p, i) => {
          const s = statuses[i];
          const last = i === PHASES.length - 1;
          const replayed = i - (PHASES.length - REPLAYED_STAGES);
          // A stage the case has reached is a button to where the page tells it; one not reached yet stays text
          const reached = !!onStage && s !== 'pending';
          const shows = p.key === 'investigation' && investigation ? investigation : SHOWS[p.key];
          return (
            <Stepper.Step
              key={p.key}
              className="lifecycle-step"
              {...(reveal && replayed >= 0 ? reveal(replayed) : {})}
              allowStepSelect={reached}
              {...(reached
                ? { 'aria-label': `${p.label}: ${words[s]}, show ${shows}`, 'data-stage': p.key }
                : { component: 'div' })}
              label={p.label}
              description={
                <Text size="xs" c={s === 'stopped' ? stopColour : 'dimmed'}>
                  {words[s]}
                </Text>
              }
              color={
                s === 'stopped'
                  ? stopColour
                  : s === 'skipped'
                    ? 'gray'
                    : last && verified && s === 'done'
                      ? 'green'
                      : undefined
              }
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
      <TechDetail kind="explain" label="What the stages mean">
        <Text size="sm" maw="68ch">
          Rehearsal is a dry run of the write at the receiver, rolled back; Approval is its release by a
          person, or the site&apos;s written policy.
        </Text>
      </TechDetail>
    </Stack>
  );
}
