import { Button, Code, CopyButton, Group, List, Paper, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import {
  IconCheck,
  IconChevronDown,
  IconCircleCheck,
  IconCopy,
  IconHandStop,
  IconProgress,
  IconUserQuestion,
  type Icon,
} from '@tabler/icons-react';
import { useState, type CSSProperties, type ReactNode } from 'react';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { gateOutcome, verification, writes } from '@/lib/status';
import { TONE_COLOURS, toneText, type Tone } from '@/lib/tone';
import { Reinvestigate } from './Closure';
import { checksOf } from './derive';
import {
  evidenceSummary,
  failedTitle,
  nextAction,
  outcomeHeadline,
  outcomeReason,
  releaseStatus,
  type CaseFacts,
} from './outcome';
import { Section } from './Section';

/** The gate's outcome in a word on the badge; the counts are written beside it. */
const GATE_LABELS: Record<string, string> = { pass: 'Passed', block: 'Blocked', unknown: 'Unknown' };

/** One labelled fact of the receipt: its name, a status badge when it has one, and the words. */
function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Stack gap={4} className="receipt-fact" style={{ minWidth: 0 }}>
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
 * One of the three cards that open the case: what happened, what Shutter did and what needs you now. Its label is a
 * heading, so each card is reached by heading; the title under it is the answer in a few words.
 */
function StoryCard({
  label,
  title,
  icon: I,
  tone,
  style,
  children,
}: {
  label: string;
  title: string;
  icon?: Icon;
  tone?: Tone;
  style?: CSSProperties;
  children?: ReactNode;
}) {
  return (
    <Paper withBorder p="sm" radius="md" style={{ minWidth: 0, ...style }} data-tone={tone}>
      <Stack gap={6}>
        <Group gap={6} wrap="nowrap" align="center">
          {I && tone ? <I size={16} aria-hidden style={{ color: toneText(tone), flexShrink: 0 }} /> : null}
          <Title
            order={3}
            fz="xs"
            fw={700}
            tt="uppercase"
            // The label keeps the body's text colour: a tone's text colour on its own tint falls short of 4.5:1 in
            // some appearances, and the icon beside it already carries the tone
            style={{
              letterSpacing: '0.04em',
              color: tone ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
            }}
          >
            {label}
          </Title>
        </Group>
        <Text fw={700} lh={1.35}>
          {title}
        </Text>
        {children}
      </Stack>
    </Paper>
  );
}

/**
 * The top of the case: three cards, what happened (the failure and what the evidence says), what Shutter did (the
 * outcome and its reason) and what needs you now (the next action, in its tone when someone has to act); then the
 * decision receipt as a band of labelled facts (the proposal, the gate, who or what released the write, the writes
 * and the verification). A stopped case's hand-off to the team follows the board, on the page. Every line is put together from the case's
 * structured facts. The receipt copies as JSON.
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
  const tone: Tone =
    next.kind === 'none'
      ? 'neutral'
      : next.kind === 'shutter'
        ? 'info'
        : c.state === 'blocked' || c.state === 'failed'
          ? 'blocking'
          : 'attention';
  const NextIcon =
    next.kind === 'none'
      ? IconCircleCheck
      : next.kind === 'shutter'
        ? IconProgress
        : c.state === 'blocked'
          ? IconHandStop
          : IconUserQuestion;
  const colour = TONE_COLOURS[tone];
  // The third card is drawn in its tone only when someone has to act; its icon and words say the same without colour
  const marked = next.kind !== 'none';
  return (
    <Section id="outcome" tour="case-outcome" title="Outcome">
      {/* By the width the card has, not the window's: beside Ask about this case the page's column is narrower */}
      <SimpleGrid type="container" cols={{ base: 1, '700px': 3 }} spacing="sm">
        <StoryCard label="What happened" title={failedTitle(c)}>
          <Text size="sm">{evidenceSummary(facts.snapshot)}</Text>
        </StoryCard>
        <StoryCard label="What Shutter did" title={outcomeHeadline(facts)}>
          <Text size="sm">{outcomeReason(facts)}</Text>
          {round > 1 ? (
            <Text size="sm">
              {`Round ${round}: the receiver changed after the approval, so the approval was revoked and the case was planned again on fresh evidence. The audit trail keeps every round.`}
            </Text>
          ) : null}
        </StoryCard>
        <StoryCard
          label="What needs you now"
          title={next.action}
          icon={NextIcon}
          tone={tone}
          style={
            marked
              ? {
                  background: `var(--mantine-color-${colour}-light)`,
                  borderColor: `var(--mantine-color-${colour}-outline)`,
                  borderWidth: 2,
                }
              : undefined
          }
        >
          {/* What (the title), who and why; the reason's code, what must hold and when to look again behind Why? */}
          {next.kind === 'person' ? (
            <KeyValueList
              labelWidth={96}
              rows={[
                ['Who', next.role],
                ['Why', b?.text || next.blocking],
                ['Escalation', next.escalate ? next.handoff : ''],
              ]}
            />
          ) : null}
          {hasWhy || (c.state === 'awaiting_approval' && onReview) ? (
            <Group gap="xs">
              {c.state === 'awaiting_approval' && onReview ? (
                // A light button on the tinted card falls short of 4.5:1 in dark mode: the default surface keeps it.
                // On a phone it takes the card's width, as the one thing to do.
                <Button size="xs" variant="default" onClick={onReview} w={{ base: '100%', sm: 'auto' }}>
                  Review the plan and decide
                </Button>
              ) : null}
              {hasWhy ? (
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
              ) : null}
            </Group>
          ) : null}
          {hasWhy && why ? (
            <Stack id="next-action-why" gap="xs">
              <KeyValueList
                labelWidth={96}
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
          {/* A withheld case (a merge or a cancel Shutter never sends) has nothing new to find: the team closes it */}
          {stopped && c.failureKind !== 'withheld' ? <Reinvestigate c={c} /> : null}
        </StoryCard>
      </SimpleGrid>
      <Paper className="receipt-band" p="md" radius="md" component="section" aria-labelledby="receipt-title">
        <Stack gap="sm">
          <Group justify="space-between" align="center" wrap="wrap" gap="xs">
            <Title order={3} fz="md" id="receipt-title">
              Decision receipt
            </Title>
            <CopyButton value={JSON.stringify(r, null, 2)} timeout={1500}>
              {({ copied, copy }) => (
                <Button
                  size="xs"
                  variant="default"
                  leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                  onClick={copy}
                >
                  {copied ? 'Copied' : 'Copy receipt as JSON'}
                </Button>
              )}
            </CopyButton>
          </Group>
          <SimpleGrid
            component="dl"
            className="receipt-facts"
            type="container"
            cols={{ base: 1, '500px': 3, '900px': 5 }}
            spacing="md"
            verticalSpacing="sm"
            m={0}
          >
            <Fact label="Proposal">
              {/* The catalogue entry and the plan digest are the plan's, in step 3, and in the copied receipt */}
              <Text size="md" fw={700}>
                {r.action}
              </Text>
            </Fact>
            <Fact label="Gate">
              {gate && gateStatus ? (
                <>
                  <StatusBadge
                    {...gateStatus}
                    label={GATE_LABELS[gate.outcome] ?? gateStatus.label}
                    size="md"
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
              {release ? <StatusBadge {...release} size="md" w="fit-content" /> : null}
              <Text size="sm">{r.decidedBy}</Text>
              {r.decidedAt ? <Timestamp iso={r.decidedAt} size="xs" c="dimmed" /> : null}
            </Fact>
            <Fact label="Writes">
              {facts.attempts === undefined ? (
                <Text size="sm">Unknown</Text>
              ) : (
                <>
                  <StatusBadge {...writes(r.writes)} size="md" w="fit-content" />
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
                <>
                  <StatusBadge {...verification(r.verificationState)} size="md" w="fit-content" />
                  {r.verification !== verification(r.verificationState).label &&
                  r.verificationState !== 'not_applicable' ? (
                    <Text size="xs" c="dimmed">
                      {r.verification}
                    </Text>
                  ) : null}
                </>
              ) : (
                // No verification state yet: the words stand alone, so the fact is never empty
                <Text size="sm">
                  {r.verification || (stopped || c.state === 'resolved' ? 'Unknown' : 'Not verified yet')}
                </Text>
              )}
            </Fact>
          </SimpleGrid>
        </Stack>
      </Paper>
    </Section>
  );
}
