import { Button, Code, CopyButton, Group, List, SimpleGrid, Stack, Text } from '@mantine/core';
import {
  IconCheck,
  IconChevronDown,
  IconCircleCheck,
  IconCopy,
  IconHandStop,
  IconProgress,
  IconUserQuestion,
} from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { gateOutcome, verification, writes } from '@/lib/status';
import { Reinvestigate } from './Closure';
import { checksOf } from './derive';
import { nextAction, outcomeHeadline, outcomeReason, releaseStatus, type CaseFacts } from './outcome';
import { EscalationPanel } from './EscalationPanel';
import { NestedSections, Section } from './Section';

/** The gate's outcome in a word on the badge; the counts are written beside it. */
const GATE_LABELS: Record<string, string> = { pass: 'Passed', block: 'Blocked', unknown: 'Unknown' };

/** One labelled fact of the receipt: its name, a status badge when it has one, and the words. */
function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Stack gap={4} style={{ minWidth: 0 }}>
      <Text component="dt" size="xs" c="dimmed" fw={600}>
        {label}
      </Text>
      <Stack component="dd" gap={4} m={0}>
        {children}
      </Stack>
    </Stack>
  );
}

/**
 * The top of the case: one outcome sentence and its reason, the decision receipt as labelled facts (the proposal,
 * the gate, who or what released the write, the writes and the verification), and the next action. Every line is
 * put together from the case's structured facts. The receipt copies as JSON.
 */
export function DecisionCard({
  facts,
  round = 1,
  onReview,
}: {
  facts: CaseFacts;
  /** The case's round of evidence and planning: a re-plan after the receiver changed starts another. */
  round?: number;
  /** Opens the gate and decision step, where the approval is decided. */
  onReview?: () => void;
}) {
  const { c, receipt: r } = facts;
  const gate = facts.plan?.gateDecisions?.at(-1);
  const gateStatus = gate ? gateOutcome(gate.outcome, checksOf(gate)) : undefined;
  const release = releaseStatus(facts);
  const next = nextAction(facts);
  const b = facts.blocked;
  const stopped = c.state === 'blocked' || c.state === 'escalated' || c.state === 'failed';
  const [why, setWhy] = useState(false);
  const hasWhy =
    next.kind === 'person' &&
    !!(b?.title || b?.code || b?.prerequisite || next.lookAgain || b?.checks?.length);
  const writesDetail = [
    r.writes ? `${r.acknowledged} acknowledged` : '',
    r.notWritten ? `${r.notWritten} attempt${r.notWritten === 1 ? '' : 's'} the receiver did not take` : '',
    r.writes && r.expectedVersion
      ? `conditional on version ${r.expectedVersion}${r.receiverEpoch ? `, epoch ${r.receiverEpoch}` : ''}`
      : '',
  ]
    .filter(Boolean)
    .join('; ');
  return (
    <Section
      id="outcome"
      tour="case-outcome"
      title="Outcome"
      aside={
        <CopyButton value={JSON.stringify(r, null, 2)} timeout={1500}>
          {({ copied, copy }) => (
            <Button
              size="xs"
              variant="light"
              leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
              onClick={copy}
            >
              {copied ? 'Copied' : 'Copy receipt as JSON'}
            </Button>
          )}
        </CopyButton>
      }
    >
      <Stack gap={4}>
        <Text size="lg" fw={700}>
          {outcomeHeadline(facts)}
        </Text>
        <Text size="sm" maw="75ch">
          {outcomeReason(facts)}
        </Text>
        {round > 1 ? (
          <Text size="sm" maw="75ch">
            {`Round ${round}: the receiver changed after the approval, so the approval was revoked and the case was planned again on fresh evidence. The audit trail keeps every round.`}
          </Text>
        ) : null}
      </Stack>
      <SimpleGrid component="dl" cols={{ base: 1, sm: 2, md: 3 }} spacing="md" verticalSpacing="sm" m={0}>
        <Fact label="Proposal">
          {/* The catalogue entry and the plan digest are the plan's, in step 3, and in the copied receipt */}
          <Text size="sm">{r.action}</Text>
        </Fact>
        <Fact label="Gate">
          {gate && gateStatus ? (
            <>
              <StatusBadge
                {...gateStatus}
                label={GATE_LABELS[gate.outcome] ?? gateStatus.label}
                w="fit-content"
              />
              <Text size="xs" c="dimmed">
                {`${gateStatus.label}, at ${gate.stage}; policy ${gate.policyVersion}`}
              </Text>
            </>
          ) : (
            <Text size="sm">{facts.plan === undefined ? 'Unknown' : 'Not checked yet'}</Text>
          )}
        </Fact>
        <Fact label="Released by">
          {release ? <StatusBadge {...release} w="fit-content" /> : null}
          <Text size="sm">{r.decidedBy}</Text>
          {r.decidedAt ? <Timestamp iso={r.decidedAt} size="xs" c="dimmed" /> : null}
        </Fact>
        <Fact label="Writes">
          {facts.attempts === undefined ? (
            <Text size="sm">Unknown</Text>
          ) : (
            <>
              <StatusBadge {...writes(r.writes)} w="fit-content" />
              {/* The badge says 0 writes; the words add only what it does not say */}
              {writesDetail ? (
                <Text size="xs" c="dimmed">
                  {writesDetail}
                </Text>
              ) : null}
            </>
          )}
        </Fact>
        <Fact label="Verification">
          {r.verificationState ? (
            <StatusBadge {...verification(r.verificationState)} w="fit-content" />
          ) : null}
          {r.verification !== verification(r.verificationState).label &&
          r.verificationState !== 'not_applicable' ? (
            <Text size="xs" c={r.verificationState ? 'dimmed' : undefined}>
              {r.verification || (stopped || c.state === 'resolved' ? 'Unknown' : 'Not verified yet')}
            </Text>
          ) : null}
        </Fact>
      </SimpleGrid>
      <StatusNotice
        tone={
          next.kind === 'none'
            ? 'neutral'
            : next.kind === 'shutter'
              ? 'info'
              : c.state === 'blocked' || c.state === 'failed'
                ? 'blocking'
                : 'attention'
        }
        icon={
          next.kind === 'none'
            ? IconCircleCheck
            : next.kind === 'shutter'
              ? IconProgress
              : c.state === 'blocked'
                ? IconHandStop
                : IconUserQuestion
        }
        title={
          <Text span fz="md" fw={700} lh={1.4}>
            {`Next action: ${next.action}`}
          </Text>
        }
      >
        <Stack gap="xs">
          {/* What (the title), who and why; the reason's code, what must hold and when to look again behind Why? */}
          {next.kind === 'person' ? (
            <KeyValueList
              rows={[
                ['Who', next.role],
                ['Why', b?.text || next.blocking],
                ['Escalation', next.escalate ? next.handoff : ''],
              ]}
            />
          ) : null}
          {hasWhy ? (
            <Group>
              <Button
                size="xs"
                variant="default"
                onClick={() => setWhy((w) => !w)}
                aria-expanded={why}
                aria-controls="next-action-why"
                leftSection={
                  <IconChevronDown
                    size={14}
                    aria-hidden
                    style={{ transform: why ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
                  />
                }
              >
                Why?
              </Button>
            </Group>
          ) : null}
          {hasWhy && why ? (
            <Stack id="next-action-why" gap="xs">
              <KeyValueList
                rows={[
                  ['Reason', b?.title ?? ''],
                  ['Reason code', b?.code ? <Code key="c">{b.code}</Code> : ''],
                  ['Why it waits', b?.text && b.prerequisite ? b.prerequisite : ''],
                  ['Look again when', next.lookAgain],
                ]}
              />
              {b?.checks?.length ? (
                <List size="sm" spacing={2}>
                  {b.checks.map((ch) => (
                    <List.Item key={ch.check}>
                      {humanize(ch.check)}: {ch.reason_code}, {ch.detail}
                    </List.Item>
                  ))}
                </List>
              ) : null}
            </Stack>
          ) : (
            <div id="next-action-why" hidden />
          )}
          {c.state === 'awaiting_approval' && onReview ? (
            <Group>
              {/* A light button on the tinted notice falls short of 4.5:1 in dark mode: the default surface keeps it */}
              <Button size="xs" variant="default" onClick={onReview}>
                Review the plan and decide
              </Button>
            </Group>
          ) : null}
          {/* A withheld case (a merge or a cancel Shutter never sends) has nothing new to find: the team closes it */}
          {stopped && c.failureKind !== 'withheld' ? <Reinvestigate c={c} /> : null}
          {/* The hand-off to the team, here with the action it serves: the main button only when it is the action */}
          {stopped ? (
            <NestedSections>
              <EscalationPanel c={c} primary={next.escalate} />
            </NestedSections>
          ) : null}
        </Stack>
      </StatusNotice>
    </Section>
  );
}
