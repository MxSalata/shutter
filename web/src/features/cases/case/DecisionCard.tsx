import {
  Box,
  Button,
  Code,
  Collapse,
  CopyButton,
  Group,
  List,
  Paper,
  SimpleGrid,
  Stack,
  Text,
  Title,
  UnstyledButton,
} from '@mantine/core';
import {
  IconArrowsLeftRight,
  IconCheck,
  IconChevronDown,
  IconCircleCheck,
  IconCopy,
  IconHandStop,
  IconProgress,
  IconUserQuestion,
  type Icon,
} from '@tabler/icons-react';
import { useEffect, useState, type CSSProperties, type ReactNode } from 'react';
import { CheckStrip } from '@/components/CheckStrip';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { caseOutcome, gateOutcome, verification, writes, type CaseOutcome } from '@/lib/status';
import { CATEGORY_TEXT } from '@/lib/categories';
import { SHOW_NEXT_ACTION } from '@/lib/events';
import { useGuideTarget } from '@/lib/guideDock';
import { usePrefersReducedMotion } from '@/lib/motion';
import { TONE_COLOURS, TONE_ICONS, toneText, type Tone } from '@/lib/tone';
import { Reinvestigate } from './Closure';
import { checksOf } from './derive';
import { gateFactLabel, laterChecksLine } from './gateWords';
import { NextActionPrecedents } from './Precedents';
import { bandKind, bandStartsOpen, rememberBand } from './outcomeBand';
import {
  actionHead,
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
import { CorrectionDraft } from './CorrectionDraft';
import { caseReceiver, correctionStepsOf } from './receiver';

/** The gate's outcome in a word on the badge; the counts are written beside it. */
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
  id,
  children,
}: {
  label: string;
  title: string;
  icon?: Icon;
  tone?: Tone;
  style?: CSSProperties;
  className?: string;
  /** The card's id; its heading is `<id>-title`, focusable from script (the case's action button moves focus there). */
  id?: string;
  children?: ReactNode;
}) {
  return (
    // One size for the three: the same padding and type, and as tall as the tallest in their row (the grid stretches them)
    <Paper
      withBorder
      p="sm"
      radius="md"
      id={id}
      style={{ minWidth: 0, ...style }}
      className={['story-card', className].filter(Boolean).join(' ')}
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
            id={id ? `${id}-title` : undefined}
            tabIndex={id ? -1 : undefined}
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
        <Text fw={700} size="md" lh={1.35}>
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
 * The top of the case, as one band in the outcome's tone: its heading, "Outcome", is the band's disclosure, with the
 * outcome in a sentence beside it (20 px, the case list's long label), so a closed band still says it. Open, it shows
 * three cards of one size, what happened (the failure and what the evidence says), what Shutter did (the action it took,
 * since the band says what came of it) and what needs you now (the next action, in its tone when someone has to act,
 * kept short: a long action's rest, why it waits and any correction steps sit behind its details); then the decision
 * receipt as a band of labelled facts, one plain caption each, with the versions, keys and times one click away (closed
 * in both modes, to keep the band short). Every line is put together from the case's structured facts. The receipt
 * copies as JSON.
 *
 * The band starts open on a case a person may still act on and closed on a closed one, and remembers a reader's choice
 * in this browser (`outcomeBand.ts`); it opens while the guide points at it or at the receipt, and when the case's
 * action button asks for "What needs you now".
 */
export function DecisionCard({
  facts,
  round = 1,
  onReview,
  outcome,
  fading = false,
  onSeePrecedents,
  onCompare,
  comparable = false,
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
  /** Opens the side by side of S8's two runs. */
  onCompare?: () => void;
  /** Both of S8's runs are here to compare. */
  comparable?: boolean;
}) {
  const { c, receipt: r } = facts;
  const verdict = outcome ?? caseOutcome(outcomeCaseOf(facts));
  const OutcomeIcon = verdict.icon ?? TONE_ICONS[verdict.tone];
  const gate = facts.plan?.gateDecisions?.at(-1);
  const checks = gate ? checksOf(gate) : [];
  const gateStatus = gate ? gateOutcome(gate.outcome, checks) : undefined;
  const writesNothing = !!facts.plan?.plan && facts.plan.plan.disposition !== 'resend';
  const laterLine = gate?.outcome === 'pass' && !writesNothing ? laterChecksLine(checks) : '';
  const release = releaseStatus(facts);
  const next = nextAction(facts);
  const b = facts.blocked;
  const stopped = c.state === 'blocked' || c.state === 'escalated' || c.state === 'failed';
  const [why, setWhy] = useState(false);
  const correction = correctionStepsOf(facts.plan);
  // A long next action heads its card in a few words; the rest of it waits behind the card's details
  const { head: action, rest: actionRest } = actionHead(next.action);
  // A closed case with an outcome its scenario doesn't expect has nothing pending, and saying only that reads as all clear
  const notExpected = verdict.key === 'not-as-expected' && next.kind === 'none';
  // "See the board's run" only from the run by Rules only, and only where the board's run exists to see
  const s8Wrong = notExpected && c.scenario === 'S8' && c.mode === 'rules' && r.writes > 0 && comparable;
  const more = !!actionRest || !!correction;
  const hasWhy =
    next.kind === 'person' &&
    (more ||
      !!(
        b?.title ||
        b?.code ||
        b?.text ||
        next.blocking ||
        b?.prerequisite ||
        next.lookAgain ||
        b?.checks?.length
      ));
  // The band's disclosure: the kind of case is read once, so a case that closes while the page is open (the trial's
  // replay after an approval) keeps its band as it was
  const [kind] = useState(() => bandKind(c));
  const toured = useGuideTarget();
  const tourShows = (t: string | null) => t === 'case-outcome' || t === 'case-receipt';
  const [open, setOpen] = useState(() => bandStartsOpen(kind) || tourShows(toured));
  const [seenTour, setSeenTour] = useState(toured);
  if (seenTour !== toured) {
    setSeenTour(toured);
    if (tourShows(toured)) setOpen(true);
  }
  const toggle = () => {
    setOpen(!open);
    rememberBand(kind, !open);
  };
  const reduced = usePrefersReducedMotion();
  // The case's action button: open the band, the card's details where it has some, then the card in view and focused
  useEffect(() => {
    const show = () => {
      const opening = !open;
      setOpen(true);
      if (hasWhy) setWhy(true);
      window.setTimeout(
        () => {
          document
            .getElementById('next-action')
            ?.scrollIntoView?.({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
          document.getElementById('next-action-title')?.focus({ preventScroll: true });
        },
        opening && !reduced ? 200 : 0,
      );
    };
    window.addEventListener(SHOW_NEXT_ACTION, show);
    return () => window.removeEventListener(SHOW_NEXT_ACTION, show);
  }, [open, hasWhy, reduced]);
  const tone: Tone =
    next.kind === 'none'
      ? 'neutral'
      : next.kind === 'shutter'
        ? 'info'
        : c.state === 'blocked' || c.state === 'failed'
          ? 'blocking'
          : 'attention';
  const NextIcon = notExpected
    ? OutcomeIcon
    : next.kind === 'none'
      ? IconCircleCheck
      : next.kind === 'shutter'
        ? IconProgress
        : c.state === 'blocked'
          ? IconHandStop
          : IconUserQuestion;
  const colour = TONE_COLOURS[tone];
  const receiver = caseReceiver(c, facts.snapshot);
  const category = receiver.category ? CATEGORY_TEXT[receiver.category] : undefined;
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
      data-open={open}
      p={{ base: 'sm', sm: 'md' }}
      radius="md"
      mb="md"
    >
      {/* The heading is the band's disclosure; the outcome beside it stays in view when the band is closed */}
      <Group gap="xs" wrap="wrap" align="center" style={{ rowGap: 4 }}>
        <Title order={2} id="outcome-title" fz="lg" lh={1.3}>
          <UnstyledButton
            className="outcome-toggle"
            aria-expanded={open}
            aria-controls="outcome-body"
            onClick={toggle}
          >
            <IconChevronDown
              size={18}
              aria-hidden
              style={{
                transform: open ? 'rotate(180deg)' : undefined,
                transition: 'transform 150ms',
                flex: 'none',
              }}
            />
            Outcome
          </UnstyledButton>
        </Title>
        {/* The outcome in words, not a heading (the cards' headings follow); its icon only repeats it */}
        <Group
          key={fading ? verdict.label : undefined}
          gap={8}
          wrap="nowrap"
          align="flex-start"
          style={{
            minWidth: 0,
            ...(fading ? { animation: 'trial-fade var(--motion-base) var(--motion-ease) 1' } : {}),
          }}
        >
          <OutcomeIcon
            size={22}
            stroke={1.8}
            aria-hidden
            style={{ color: toneText(verdict.tone), flex: 'none', marginTop: 2 }}
          />
          <Text className="outcome-statement" data-testid="outcome-line" maw="68ch">
            {verdict.label}
          </Text>
        </Group>
      </Group>
      <Collapse in={open} transitionDuration={150}>
        <Box id="outcome-body" pt="sm" inert={!open || undefined}>
          <Stack gap="sm">
            {/* By the width the band has, not the window's: beside Ask about this case the page's column is narrower.
                The three cards are one size: in a row, each as tall as the tallest; once the reader opens the third's
                details, each keeps its own height, so the other two do not stretch to the long text. */}
            <SimpleGrid
              type="container"
              cols={{ base: 1, '700px': 3 }}
              spacing="sm"
              style={{ alignItems: why ? 'start' : 'stretch' }}
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
                    {/* Reinvestigate starts a round too, on a case nobody may have approved */}
                    {(facts.approvals?.approvals ?? []).some((a) => a.revoked)
                      ? `Round ${round}: the receiver changed after the approval, so the approval was revoked and the case was planned again on fresh evidence. The audit trail keeps every round.`
                      : `Round ${round}: the case was investigated again on fresh evidence. The audit trail keeps every round.`}
                  </Text>
                ) : null}
              </StoryCard>
              <StoryCard
                id="next-action"
                label="What needs you now"
                title={
                  s8Wrong
                    ? "This run wrote what the scenario says it shouldn't: see the board's run"
                    : notExpected
                      ? `Nothing is pending, but this isn't what ${c.scenario} expects`
                      : action
                }
                icon={NextIcon}
                tone={tone}
                className={marked ? 'tone-tint' : undefined}
                style={{
                  scrollMarginTop: 'calc(var(--shutter-header-h) + 3.5rem)',
                  ...(marked
                    ? {
                        background: `var(--mantine-color-${colour}-light)`,
                        borderColor: `var(--mantine-color-${colour}-outline)`,
                        borderWidth: 2,
                      }
                    : {}),
                }}
              >
                {s8Wrong && onCompare ? (
                  <Group gap="xs">
                    <Button
                      size="xs"
                      variant="default"
                      leftSection={<IconArrowsLeftRight size={14} aria-hidden />}
                      onClick={onCompare}
                    >
                      Compare the two runs
                    </Button>
                  </Group>
                ) : null}
                {/* What (the title) and who; the rest of a long action, why, the reason's code, what must hold, when to
                    look again and any steps that correct a receiver's history behind the details */}
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
                      // A light button on the tinted card falls short of 4.5:1 in dark mode: the default surface keeps
                      // it. On a phone it takes the card's width, as the one thing to do.
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
                        {more ? 'Why, and what to do' : 'Why?'}
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
                    {actionRest ? (
                      <Text size="sm" data-testid="next-action-rest">
                        {actionRest}
                      </Text>
                    ) : null}
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
                  </Stack>
                ) : (
                  <div id="next-action-why" hidden />
                )}
                {/* A withheld case (a merge or a cancel Shutter never sends) has nothing new to find: the team closes it */}
                {stopped && c.failureKind !== 'withheld' ? <Reinvestigate c={c} /> : null}
              </StoryCard>
            </SimpleGrid>
            {hasWhy && why && correction ? (
              <CorrectionDraft caseId={c.caseId} correction={correction} />
            ) : null}
            <Paper
              className="receipt-band"
              p="sm"
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
                            gateFactLabel(gate.outcome, checks, c.state, writesNothing) ?? gateStatus.label
                          }
                          size="md"
                          w="fit-content"
                        />
                        <CheckStrip checks={checks} />
                        {laterLine ? <Text size="sm">{laterLine}</Text> : null}
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
                        {r.verification ||
                          (stopped || c.state === 'resolved' ? 'Unknown' : 'Not verified yet')}
                      </Text>
                    )}
                  </Fact>
                </SimpleGrid>
                {/* The record's exact terms, for the engineer: a click away in both modes, so the band stays short */}
                <TechDetail label="Versions, keys and times" kind="data" defaultOpen={false}>
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
        </Box>
      </Collapse>
    </Paper>
  );
}
