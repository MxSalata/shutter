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
import { CheckStrip } from '@/components/CheckStrip';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { caseOutcome, gateOutcome, verification, writes, type CaseOutcome } from '@/lib/status';
import { CATEGORY_TEXT } from '@/lib/categories';
import { TONE_COLOURS, TONE_ICONS, toneText, type Tone } from '@/lib/tone';
import { Reinvestigate } from './Closure';
import { checksOf } from './derive';
import { NextActionPrecedents } from './Precedents';
import {
  actionHeadline,
  evidenceSummary,
  failedTitle,
  nextAction,
  outcomeCaseOf,
  outcomeReason,
  releaseStatus,
  type CaseFacts,
} from './outcome';
import { proposalCaption, writesCaption, writesDetail } from './receipt';
import { caseReceiver, correctionStepsOf } from './receiver';

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
  className,
  children,
}: {
  label: string;
  title: string;
  icon?: Icon;
  tone?: Tone;
  style?: CSSProperties;
  className?: string;
  children?: ReactNode;
}) {
  return (
    <Paper
      withBorder
      p="sm"
      radius="md"
      style={{ minWidth: 0, ...style }}
      className={className}
      data-tone={tone}
    >
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

/** The verifier's own outcomes, whose summary the receipt's details give; the others say why there was none. */
const VERIFIER_OUTCOMES = ['verified', 'unresolved', 'not_committed', 'failed'];

/**
 * The top of the case, as one band in the outcome's tone: the outcome in a sentence (24 px, the case list's long
 * label), then three cards, what happened (the failure and what the evidence says), what Shutter did (the action it
 * took, since the band says what came of it) and what needs you now (the next action, in its tone when someone has to
 * act; short when nothing is pending); then the decision receipt as a band of labelled facts, one plain caption each,
 * with the versions, keys and times one click away (open in Technical). Every line is put together from the case's
 * structured facts. The receipt copies as JSON.
 */
export function DecisionCard({
  facts,
  round = 1,
  onReview,
  outcome,
  fading = false,
  onSeePrecedents,
}: {
  facts: CaseFacts;
  /** The case's round of evidence and planning: a re-plan after the receiver changed starts another. */
  round?: number;
  /** Opens the gate and decision step, where the approval is decided. */
  onReview?: () => void;
  /** What came of the case, with its scenario's expectation; from the facts alone when not given. */
  outcome?: CaseOutcome;
  /** The outcome has just changed in the trial's replay: its words fade in. */
  fading?: boolean;
  /** Opens the precedents' list in the Audit trail. */
  onSeePrecedents?: () => void;
}) {
  const { c, receipt: r } = facts;
  const verdict = outcome ?? caseOutcome(outcomeCaseOf(facts));
  const OutcomeIcon = verdict.icon ?? TONE_ICONS[verdict.tone];
  const gate = facts.plan?.gateDecisions?.at(-1);
  const checks = gate ? checksOf(gate) : [];
  const gateStatus = gate ? gateOutcome(gate.outcome, checks) : undefined;
  const writesNothing = !!facts.plan?.plan && facts.plan.plan.disposition !== 'resend';
  const release = releaseStatus(facts);
  const next = nextAction(facts);
  const b = facts.blocked;
  const stopped = c.state === 'blocked' || c.state === 'escalated' || c.state === 'failed';
  const [why, setWhy] = useState(false);
  const hasWhy =
    next.kind === 'person' &&
    !!(
      b?.title ||
      b?.code ||
      b?.text ||
      next.blocking ||
      b?.prerequisite ||
      next.lookAgain ||
      b?.checks?.length
    );
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
  const receiver = caseReceiver(c, facts.snapshot);
  const category = receiver.category ? CATEGORY_TEXT[receiver.category] : undefined;
  const correction = correctionStepsOf(facts.plan);
  // The third card is drawn in its tone only when someone has to act; its icon and words say the same without colour
  const marked = next.kind !== 'none';
  const caption = writesCaption(r);
  const verifierSummary = VERIFIER_OUTCOMES.includes(r.verificationState) ? r.verification : '';
  const proposal = proposalCaption(r);
  return (
    <Paper
      component="section"
      id="outcome"
      aria-labelledby="outcome-title"
      data-tour="case-outcome"
      className="hero-band outcome-band"
      data-tone={verdict.tone}
      p={{ base: 'md', sm: 'lg' }}
      radius="md"
      mb="lg"
    >
      <Stack gap="md">
        <Stack gap={6}>
          <Title order={2} id="outcome-title" tabIndex={-1}>
            Outcome
          </Title>
          {/* The outcome in words, not a heading (the cards' headings follow); its icon only repeats it */}
          <Group
            key={fading ? verdict.label : undefined}
            gap="sm"
            wrap="nowrap"
            align="flex-start"
            style={fading ? { animation: 'trial-fade var(--motion-base) var(--motion-ease) 1' } : undefined}
          >
            <OutcomeIcon
              size={28}
              stroke={1.8}
              aria-hidden
              style={{ color: toneText(verdict.tone), flex: 'none' }}
            />
            <Text className="hero-statement" data-testid="outcome-line" maw="68ch">
              {verdict.label}
            </Text>
          </Group>
        </Stack>
        {/* By the width the band has, not the window's: beside Ask about this case the page's column is narrower.
            Each card is as tall as its words: a short card stays short. */}
        <SimpleGrid
          type="container"
          cols={{ base: 1, '700px': 3 }}
          spacing="sm"
          style={{ alignItems: 'start' }}
        >
          <StoryCard label="What happened" title={failedTitle(c)}>
            <Text size="sm">{evidenceSummary(facts.snapshot)}</Text>
          </StoryCard>
          <StoryCard label="What Shutter did" title={actionHeadline(facts)}>
            {/* The receiver the case is about, and its category as the evidence recorded it */}
            <Group gap={6} wrap="wrap" data-testid="case-receiver">
              <Text size="sm">At {receiver.name}</Text>
              {category ? (
                <StatusBadge
                  tone="neutral"
                  icon={null}
                  label={category.label}
                  hint={`${category.gist}. ${category.overtaken}`}
                />
              ) : null}
            </Group>
            {/* The category's meaning in words, not only in the badge's tooltip, which touch screens never show */}
            {category ? (
              <Text size="sm" c="dimmed" data-testid="case-receiver-gist">
                {`${category.gist}.`}
              </Text>
            ) : null}
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
            className={marked ? 'tone-tint' : undefined}
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
            {/* What (the title) and who; why, the reason's code, what must hold and when to look again behind Why? */}
            {next.kind === 'person' ? (
              <KeyValueList
                labelWidth={96}
                rows={[
                  ['Who', next.role],
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
                        style={{
                          transform: why ? 'rotate(180deg)' : undefined,
                          transition: 'transform 150ms',
                        }}
                      />
                    }
                  >
                    Why?
                  </Button>
                ) : null}
              </Group>
            ) : null}
            {/* What approvers decided before on these conditions here, under the button: what happened, not what to do */}
            {c.state === 'awaiting_approval' ? (
              <NextActionPrecedents caseId={c.caseId} snapshot={facts.snapshot} onSee={onSeePrecedents} />
            ) : null}
            {hasWhy && why ? (
              <Stack id="next-action-why" gap="xs">
                <KeyValueList
                  labelWidth={96}
                  rows={[
                    ['Reason', b?.title ?? ''],
                    ['Why', b?.text || next.blocking],
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
            {correction ? (
              <Stack gap={4} data-testid="correction-steps">
                <Title order={4} fz="sm">
                  {`Correcting the history at ${correction.receiver || receiver.name}`}
                </Title>
                <List type="ordered" size="sm" spacing={4}>
                  {correction.steps.map((step, i) => (
                    <List.Item key={i}>{step}</List.Item>
                  ))}
                </List>
              </Stack>
            ) : null}
            {/* A withheld case (a merge or a cancel Shutter never sends) has nothing new to find: the team closes it */}
            {stopped && c.failureKind !== 'withheld' ? <Reinvestigate c={c} /> : null}
          </StoryCard>
        </SimpleGrid>
        <Paper
          className="receipt-band"
          p="md"
          radius="md"
          component="section"
          aria-labelledby="receipt-title"
          data-tour="case-receipt"
        >
          <Stack gap="sm">
            <Group justify="space-between" align="center" wrap="wrap" gap="xs">
              <Title order={3} id="receipt-title">
                Decision receipt
              </Title>
              <CopyButton value={JSON.stringify(r, null, 2)} timeout={1500}>
                {({ copied, copy }) => (
                  <Button
                    size="xs"
                    variant="default"
                    leftSection={
                      copied ? <IconCheck size={14} aria-hidden /> : <IconCopy size={14} aria-hidden />
                    }
                    onClick={copy}
                    data-tour-action="copy-receipt"
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
                <Text size="md" fw={700}>
                  {proposal}
                </Text>
              </Fact>
              <Fact label="Gate">
                {gate && gateStatus ? (
                  <>
                    <StatusBadge
                      {...gateStatus}
                      // Its scope beside a plan that writes nothing, so a green check is not read as leave to write
                      label={
                        gate.outcome === 'pass' && writesNothing
                          ? 'Passed: the plan writes nothing'
                          : (GATE_LABELS[gate.outcome] ?? gateStatus.label)
                      }
                      size="md"
                      w="fit-content"
                    />
                    <CheckStrip checks={checks} />
                  </>
                ) : (
                  <Text size="sm">{facts.plan === undefined ? 'Unknown' : 'Not checked yet'}</Text>
                )}
              </Fact>
              <Fact label="Released by">
                {release ? <StatusBadge {...release} size="md" w="fit-content" /> : null}
                <Text size="sm">{r.decidedBy}</Text>
              </Fact>
              <Fact label="Writes">
                {facts.attempts === undefined ? (
                  <Text size="sm">Unknown</Text>
                ) : (
                  <>
                    <StatusBadge {...writes(r.writes)} size="md" w="fit-content" />
                    {/* The badge says 0 writes; the words add only what it does not say */}
                    {caption ? <Text size="sm">{caption}</Text> : null}
                  </>
                )}
              </Fact>
              <Fact label="Verification">
                {r.verificationState ? (
                  <StatusBadge {...verification(r.verificationState)} size="md" w="fit-content" />
                ) : (
                  // No verification state yet: the words stand alone, so the fact is never empty
                  <Text size="sm">
                    {r.verification || (stopped || c.state === 'resolved' ? 'Unknown' : 'Not verified yet')}
                  </Text>
                )}
              </Fact>
            </SimpleGrid>
            {/* The record's exact terms, for the engineer: in Technical open, in Plain a click away */}
            <TechDetail label="Versions, keys and times" kind="data">
              <KeyValueList
                labelWidth={150}
                rows={[
                  ['Proposal', proposal !== r.action ? r.action : ''],
                  [
                    'Plan',
                    r.planVersion !== null
                      ? `v${r.planVersion}${r.catalogueEntry ? `, catalogue entry ${r.catalogueEntry}` : ''}`
                      : '',
                  ],
                  [
                    'Gate',
                    gate && gateStatus
                      ? `${gateStatus.label}, at ${gate.stage}; policy ${gate.policyVersion}`
                      : '',
                  ],
                  ['Gate checked', gate?.at ? <Timestamp key="g" iso={gate.at} /> : ''],
                  ['Released', r.decidedAt ? <Timestamp key="d" iso={r.decidedAt} /> : ''],
                  ['Earlier approval', r.earlierApproval],
                  ['Writes', writesDetail(r)],
                  ['Verification', verifierSummary],
                  [
                    'Plan digest',
                    r.planDigest ? <Digest key="p" value={r.planDigest} label="plan digest" /> : '',
                  ],
                  [
                    'Snapshot digest',
                    r.snapshotDigest ? (
                      <Digest key="s" value={r.snapshotDigest} label="snapshot digest" />
                    ) : (
                      ''
                    ),
                  ],
                ]}
              />
            </TechDetail>
          </Stack>
        </Paper>
      </Stack>
    </Paper>
  );
}
