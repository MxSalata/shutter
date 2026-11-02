import {
  ActionIcon,
  Anchor,
  Box,
  Card,
  Chip,
  Group,
  List,
  NativeSelect,
  Paper,
  SimpleGrid,
  Stack,
  Table,
  Text,
  Title,
  Tooltip,
  UnstyledButton,
  VisuallyHidden,
} from '@mantine/core';
import { IconChartBar, IconCheck, IconFilter, IconInfoCircle } from '@tabler/icons-react';
import { useId, useMemo, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router';
import evaluation from '../../../../docs/readme/evaluation.json';
import evaluationText from '../../../../docs/readme/evaluation.md?raw';
import comparisonText from '../../../../docs/readme/comparison.md?raw';
import boundary from '../../../../docs/readme/boundary.json';
import { useCases } from '@/api/hooks';
import type { CaseSummary } from '@/api/types';
import { AgreementDots } from '@/components/AgreementDots';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { ComparisonBars } from '@/components/ComparisonBars';
import { HeroBand } from '@/components/HeroBand';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { DispositionBadge } from '@/components/StateBadge';
import { StatTile } from '@/components/StatTile';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { formatDuration, formatInt, formatUsd, formatUtc, humanize, plural } from '@/lib/format';
import { hueVar, MEMBERS } from '@/lib/hues';
import { usePrefersReducedMotion } from '@/lib/motion';
import { proofFrom, type PlayedResult, type Proof, type ProofSource } from '@/lib/proof';
import type { Tone } from '@/lib/tone';
import { useTechnical } from '@/stores/appearance';
import { HINT_EVENTS } from '@/theme';
import {
  AGREEMENT_LEVELS,
  agreementSlug,
  andList,
  comparisonCells,
  dayRange,
  filterPasses,
  firstSentence,
  levelPattern,
  notYetMeasured,
  ordinal,
  outweighedIn,
  passKey,
  passName,
  passPlayed,
  planDiffers,
  proposedPlan,
  readFilters,
  rulesMissed,
  SHOW_LABELS,
  SPECIALISTS,
  type BoundaryChecks,
  type Evaluation,
  type EvaluationConfidence,
  type EvaluationMember,
  type EvaluationPass,
  type PassFilters,
  type Specialist,
} from './evaluation';
import './EvaluationPage.css';

/**
 * How the board decides, from docs/readme/evaluation.json: the document scripts/evaluate.py writes from the runs
 * recorded with the real agents, read here at build time (never copied by hand), with the "Not yet measured" list
 * from evaluation.md, the played outcomes' words from comparison.md, and what the boundary refuses from
 * docs/readme/boundary.json, which tests/e2e/boundary_check.py writes. The headline's figures come through lib/proof.ts,
 * so they read as the other pages' proof does; a figure the document cannot give leaves its sentence out.
 */
const EVALUATION = evaluation as unknown as Evaluation;
const NOT_YET = notYetMeasured(evaluationText);
const COMPARISON = comparisonCells(comparisonText);
const BOUNDARY: BoundaryChecks = boundary;
const day = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

/** One group of the specialists' confidence; scripts/evaluate.py writes an empty group as its count alone. */
function confidenceGroup(c: EvaluationConfidence): string {
  if (!c.n || c.min === undefined || c.max === undefined || c.mean === undefined) return 'none';
  return `${c.n}, from ${c.min.toFixed(2)} to ${c.max.toFixed(2)} (mean ${c.mean.toFixed(2)})`;
}

/** What the scenario expects, or why the pass is not scored against it. */
function expected(p: EvaluationPass): string {
  if (!p.scored) return 'Not scored: planned again after the change';
  const others = (p.expected.acceptable ?? [])
    .filter((a) => a !== p.expected.disposition)
    .map((a) => humanize(a).toLowerCase());
  // An incident's case is scored against the entry the matcher found in its evidence, which `from` names
  const from = p.incident && p.expected.from ? ` (${p.expected.from})` : '';
  return `${humanize(p.expected.disposition)}${others.length ? ` (or ${others.join(', ')})` : ''}${from}`;
}

/** The pass's tokens as the provider bills them: uncached input, cache reads and writes, output. */
function tokens(p: EvaluationPass): string {
  const parts = [`${formatInt(p.prompt_tokens)} in`, `${formatInt(p.cache_read_tokens)} cached`];
  if (p.cache_write_tokens) parts.push(`${formatInt(p.cache_write_tokens)} cache written`);
  parts.push(`${formatInt(p.completion_tokens)} out`);
  return parts.join(' · ');
}

/** A longer note behind an info button, one hover, focus or tap away; it is the button's description too. */
function InfoTip({ label, text }: { label: string; text: string }) {
  const id = useId();
  return (
    <>
      <Tooltip label={text} multiline maw={320} events={HINT_EVENTS}>
        <ActionIcon variant="subtle" color="gray" size="sm" aria-label={label} aria-describedby={id} ml={4}>
          <IconInfoCircle size={14} aria-hidden />
        </ActionIcon>
      </Tooltip>
      <span id={id} hidden>
        {text}
      </span>
    </>
  );
}

/** A mark that filters the table: pressed while its filter is on. */
function MarkToggle({
  pressed,
  onToggle,
  tone,
  label,
}: {
  pressed: boolean;
  onToggle: () => void;
  tone: Tone;
  label: string;
}) {
  return (
    <UnstyledButton className="eval-toggle" aria-pressed={pressed} onClick={onToggle}>
      <StatusBadge tone={tone} label={label} />
    </UnstyledButton>
  );
}

/** The played marks' tones and words: the board's, and rules alone's (a stop by the gate is neutral: nothing wrote). */
const BOARD_MARKS: Partial<Record<PlayedResult, { tone: Tone; label: string }>> = {
  'as-expected': { tone: 'positive', label: 'Board: as expected' },
  differs: { tone: 'blocking', label: 'Board: not as expected' },
  'not-played': { tone: 'neutral', label: 'Board: not played' },
};
const RULES_MARKS: Record<PlayedResult, { tone: Tone; label: string }> = {
  'as-expected': { tone: 'positive', label: 'Rules alone: as expected' },
  stopped: { tone: 'neutral', label: 'Rules alone: stopped by the gate' },
  'wrote-wrongly': { tone: 'blocking', label: 'Rules alone: wrote, not as expected' },
  differs: { tone: 'blocking', label: 'Rules alone: not as expected' },
  'not-played': { tone: 'neutral', label: 'Rules alone: not played' },
};

/**
 * A row's edge: blocking when the board's plan, or the board played end to end, was not as expected; information
 * (worth seeing) when only rules alone was not; none otherwise, so attention stays for a person being needed.
 */
function rowTone(p: EvaluationPass): Tone | undefined {
  const played = passPlayed(p);
  if (planDiffers(p) || played?.board === 'differs') return 'blocking';
  if (played && rulesMissed(played.rules)) return 'info';
  return undefined;
}

/** A specialist's proposal, its own confidence and, in a scored pass, whether the plan set it aside. */
function MemberCell({
  m,
  outweighed,
  term,
}: {
  m: EvaluationMember | undefined;
  outweighed: boolean;
  /** The page's first "outweighed": the word carries its definition. */
  term: boolean;
}) {
  if (!m) return <Text size="sm">-</Text>;
  const confidence =
    m.confidence !== null && m.confidence !== undefined ? `${Math.round(m.confidence * 100)}%` : '';
  return (
    <Stack gap={2} align="flex-start">
      <DispositionBadge disposition={m.disposition} />
      {confidence || outweighed ? (
        <Text size="xs" c="dimmed">
          {confidence ? (
            <>
              <VisuallyHidden>confidence </VisuallyHidden>
              {confidence}
            </>
          ) : null}
          {confidence && outweighed ? ' · ' : null}
          {outweighed ? term ? <Term term="outweighed">outweighed</Term> : 'outweighed' : null}
        </Text>
      ) : null}
    </Stack>
  );
}

/** The plan: its action, the catalogue entry it cites with who that entry says decides, and the agreement's dots. */
function PlanCell({ p }: { p: EvaluationPass }) {
  const m = p.members.coordinator;
  return (
    <Stack gap={4} align="flex-start">
      {m ? <DispositionBadge disposition={m.disposition} /> : <Text size="sm">-</Text>}
      {planDiffers(p) ? <StatusBadge tone="blocking" label="Not as expected" /> : null}
      {p.catalogue_entry ? (
        <CodeChip data-label="Entry">
          {p.catalogue_entry}
          {p.entry_decides ? ` · ${p.entry_decides}` : ''}
        </CodeChip>
      ) : null}
      <Box data-label="Agreement">
        <AgreementDots proposed={proposedPlan(p)} agreement={p.agreement} />
      </Box>
    </Stack>
  );
}

/** How the scenario ended when played end to end, by the board and by rules alone; the comparison's words on hover. */
function PlayedCell({ p }: { p: EvaluationPass }) {
  const played = passPlayed(p);
  if (!played)
    return (
      <Text size="xs" c="dimmed">
        Planned again: the next pass ended it
      </Text>
    );
  if (played.board === 'not-played' && played.rules === 'not-played')
    return (
      <Text size="xs" c="dimmed">
        Not played end to end
      </Text>
    );
  const words = COMPARISON[p.scenario];
  const board = BOARD_MARKS[played.board] ?? BOARD_MARKS['not-played']!;
  const rules = RULES_MARKS[played.rules];
  return (
    <Stack gap={4} align="flex-start">
      <StatusBadge {...board} hint={words?.board || undefined} />
      <StatusBadge {...rules} hint={words?.rules || undefined} />
    </Stack>
  );
}

/** The case links the page needs, from the newest 100 cases (the API has no lookup by scenario and mode). */
function useScenarioCases(): (scenario: string, mode: string) => CaseSummary | undefined {
  const cases = useCases({ limit: 100 });
  const items = cases.data?.items;
  return useMemo(() => {
    const newest = [...(items ?? [])].sort((a, b) => b.openedAt.localeCompare(a.openedAt));
    return (scenario: string, mode: string) => newest.find((c) => c.scenario === scenario && c.mode === mode);
  }, [items]);
}

/** A scenario's id, as a link to its case in the mode when one is among the newest cases; plain text when none. */
function CaseId({ id, c }: { id: string; c: CaseSummary | undefined }) {
  if (!c) return <>{id}</>;
  return (
    <Anchor component={Link} to={`/cases/${encodeURIComponent(c.caseId)}`} inherit underline="always">
      {id}
    </Anchor>
  );
}

/** The hero statement: the comparison on one base, then what the gate did with rules alone's misses. */
function heroStatement(proof: Proof): ReactNode {
  const pl = proof.played;
  const misses = proof.rulesMisses;
  if (pl)
    return (
      <>
        {`On the same ${pl.of} failures, played end to end: the board ${pl.board}, `}
        <Term term="simple-rules">simple rules</Term>
        {` ${pl.rules}.`}
        {misses && misses.total && misses.stopped.length
          ? ` The gate stopped ${misses.stopped.length} of their ${misses.total} misses.`
          : ''}
      </>
    );
  const b = proof.board;
  if (b?.scored)
    return `The board chose the expected action in ${b.matched} of ${b.scored} recorded failures.`;
  return 'No board pass has been scored yet.';
}

/** The line under the hero statement: the miss that wrote, which only the board caught. */
function heroSecond(proof: Proof): string {
  const misses = proof.rulesMisses;
  if (!misses?.wrote.length) return '';
  // "The seventh": the one miss the gate did not stop, after the six it did
  if (misses.wrote.length === 1 && misses.total > 1 && misses.stopped.length === misses.total - 1)
    return `The ${ordinal(misses.total)}, ${misses.wrote[0]}, wrote the wrong ward with every check passed. Only the board caught it.`;
  return `${andList(misses.wrote)} wrote with every check passed. Only the board caught ${misses.wrote.length === 1 ? 'it' : 'them'}.`;
}

/**
 * The headline: the hero statement and its second line, the board's proposals, the comparison played end to end on
 * one base, the cost of a pass, where the figures come from, how far the specialists agreed and the limits, all in one
 * band, so the scope and the limits sit beside the result, never further down the page.
 */
function Headline({
  data,
  proof,
  filters,
  toggle,
  caseOf,
}: {
  data: Evaluation;
  proof: Proof;
  filters: PassFilters;
  toggle: (show: string) => void;
  caseOf: (scenario: string, mode: string) => CaseSummary | undefined;
}) {
  const t = data.totals;
  const b = proof.board;
  const pl = proof.played;
  const misses = proof.rulesMisses;
  const cost = proof.costPerPass;
  const allMatched = !!b && b.scored > 0 && b.matched === b.scored;
  const second = heroSecond(proof);
  // The case page's side by side of a scenario's two cases is S8's (S8Compare), opened on its board case
  const compare = misses?.wrote.includes('S8') ? caseOf('S8', 'board') : undefined;
  const range = dayRange(proof.recordedFrom, proof.recordedTo);
  const on = proof.recordedOn;
  const provenance =
    proof.runs && range
      ? `From ${plural(proof.runs, 'run')} recorded with the real agents${on ? ` on IRIS AI Hub (build ${on.build})` : ''}, ${range}; CI replays them on every push.`
      : 'No runs have been recorded with the real agents yet.';
  const rulesCaption = pl
    ? `${pl.rules} of ${pl.of} scored passes played end to end with rules alone, no agents, ended as expected; played the same way, the board ended as expected in ${pl.board} of the same ${pl.of}`
    : '';
  const unscored = t.passes - t.scored_passes;
  const decides = proof.entryDecides;

  return (
    <HeroBand
      tone={allMatched ? 'positive' : 'info'}
      label="The board against the expected outcome"
      overline="The board against the expected outcome"
      overlineOrder={2}
      statement={heroStatement(proof)}
      tour="evaluation-headline"
    >
      {second ? (
        <Text size="md">
          {second}{' '}
          {compare ? (
            <Anchor
              component={Link}
              to={`/cases/${encodeURIComponent(compare.caseId)}?show=compare`}
              underline="always"
            >
              Compare the two cases
            </Anchor>
          ) : null}
        </Text>
      ) : null}

      <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="md" style={{ alignItems: 'start' }}>
        <StatTile
          size="hero"
          label="The board's proposals"
          labelOrder={3}
          figure={b?.scored ? `${b.matched} of ${b.scored}` : 'None scored'}
          caption="recorded failures where the board chose the expected action"
          tone={allMatched ? 'positive' : b?.scored ? 'blocking' : undefined}
          status={
            allMatched ? (
              <StatusBadge tone="positive" label="As expected" />
            ) : b?.scored ? (
              <StatusBadge tone="blocking" label={`${b.scored - b.matched} not as expected`} />
            ) : undefined
          }
        >
          <TechDetail kind="data" label="How they are counted">
            <Stack gap={2}>
              <Text size="sm">
                {b ? `${b.matched} ` : ''}
                <span>scored passes proposed the scenario&apos;s expected action</span>
              </Text>
              <Text
                size="xs"
                c="dimmed"
              >{`${t.passes} passes in ${t.cases} cases; ${unscored} not scored.`}</Text>
            </Stack>
          </TechDetail>
        </StatTile>

        <StatTile
          size="hero"
          label={
            <>
              {pl ? `Played end to end, same ${pl.of}` : 'Played end to end'}
              {pl ? <InfoTip label="How the comparison was played" text={rulesCaption} /> : null}
            </>
          }
          labelOrder={3}
          figure={pl ? undefined : 'Not played'}
          caption={pl ? undefined : 'no scored pass was played with rules alone'}
        >
          {pl ? (
            <Stack gap="xs">
              <ComparisonBars
                bars={[
                  {
                    label: 'The board',
                    value: pl.board,
                    hue: 'violet',
                    hint: `The board: ${pl.board} of ${pl.of} failures ended as expected`,
                  },
                  {
                    label: 'Simple rules',
                    value: pl.rules,
                    hue: 'gray',
                    hint: `Simple rules: ${pl.rules} of ${pl.of} failures ended as expected`,
                  },
                ]}
                of={pl.of}
                caption={`Ended as expected, of the same ${pl.of} failures`}
              />
              {misses && misses.total ? (
                <Group gap={6} wrap="wrap" className="wrap-badges">
                  {misses.stopped.length ? (
                    <MarkToggle
                      tone="neutral"
                      label={`${misses.stopped.length} stopped by the gate, nothing written`}
                      pressed={filters.show === 'rules-stopped'}
                      onToggle={() => toggle('rules-stopped')}
                    />
                  ) : null}
                  {misses.wrote.length ? (
                    <MarkToggle
                      tone="blocking"
                      label={`${misses.wrote.length} written wrongly: ${andList(misses.wrote)}`}
                      pressed={filters.show === 'rules-wrote'}
                      onToggle={() => toggle('rules-wrote')}
                    />
                  ) : null}
                </Group>
              ) : null}
            </Stack>
          ) : null}
        </StatTile>

        <StatTile
          size="hero"
          label="Cost per pass"
          labelOrder={3}
          figure={cost ? `${formatUsd(cost.min)} to ${formatUsd(cost.max)}` : 'None scored'}
          caption="at list prices"
        >
          {proof.totalUsd !== null && proof.runs ? (
            <Text size="sm">{`${formatUsd(proof.totalUsd)} for ${plural(proof.runs, 'run')}`}</Text>
          ) : null}
          <TechDetail kind="data" label="Tokens and model">
            <Stack gap={0}>
              {[
                ['Uncached input', formatInt(t.prompt_tokens)],
                [<Term key="cache" term="cache-read" />, formatInt(t.cache_read_tokens)],
                ['Output', formatInt(t.completion_tokens)],
              ].map(([k, v], i) => (
                <Group key={i} justify="space-between" gap="xs" wrap="nowrap">
                  <Text size="sm" c="dimmed">
                    {k}
                  </Text>
                  <Text size="sm" className="tabular">
                    {v}
                  </Text>
                </Group>
              ))}
              {proof.models.length ? (
                <Text size="sm" mt={4}>
                  Model <CodeChip>{proof.models.join(', ')}</CodeChip>
                </Text>
              ) : null}
            </Stack>
          </TechDetail>
        </StatTile>
      </SimpleGrid>

      <Text size="sm">{`${provenance} Nothing on this page was measured on this instance.`}</Text>
      <Sources data={data} />

      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md" style={{ alignItems: 'start' }}>
        <Paper p="md">
          <Stack gap="xs">
            <Title order={3}>Agreement</Title>
            <Text size="sm" c="dimmed">
              The dots are the three specialist agents, filled when they proposed the action the plan chose.
            </Text>
            <Stack gap={2}>
              {AGREEMENT_LEVELS.filter((level) => t.agreement[level] !== undefined).map((level) => {
                const slug = agreementSlug(level);
                const pressed = filters.show === slug;
                const n = t.agreement[level];
                return (
                  <UnstyledButton
                    key={level}
                    className="eval-toggle eval-agreement-row"
                    aria-pressed={pressed}
                    onClick={() => toggle(slug)}
                  >
                    <Group justify="space-between" wrap="nowrap" gap="sm">
                      <AgreementDots proposed={levelPattern(data.passes, level)} agreement={level} />
                      <Group gap={6} wrap="nowrap">
                        <Text size="sm" className="tabular">
                          {plural(n, 'pass', 'passes')}
                        </Text>
                        {pressed ? <IconCheck size={14} aria-hidden /> : <IconFilter size={14} aria-hidden />}
                      </Group>
                    </Group>
                  </UnstyledButton>
                );
              })}
            </Stack>
          </Stack>
        </Paper>
        <Paper p="md" data-tour="evaluation-limits">
          <Stack gap="xs">
            <Title order={3}>Limits</Title>
            <Text size="sm">
              {`${plural(t.scenarios, 'scenario')}, ${plural(t.cases, 'case')}, ${formatInt(t.passes)} `}
              <Term term="pass">{t.passes === 1 ? 'pass' : 'passes'}</Term>. A match shows agreement with each
              scenario&apos;s expected outcome; it is not evidence of general reliability.
              {decides
                ? ` The plan cited an entry the site's policy may settle in ${decides.policy} of ${decides.of}, one needing the board in ${decides.board}, a person in ${decides.person}.`
                : ''}{' '}
              {/* The hash is the router's, so the link scrolls rather than changing it */}
              <Anchor
                component="button"
                type="button"
                size="sm"
                onClick={() => {
                  const target = document.getElementById('not-measured-title');
                  target?.scrollIntoView?.({ block: 'start' });
                  target?.focus({ preventScroll: true });
                }}
              >
                What is not yet measured
              </Anchor>
            </Text>
          </Stack>
        </Paper>
      </SimpleGrid>
    </HeroBand>
  );
}

/** Where the figures come from, in full: the provenance as the evaluation states it, and every figure in a sentence. */
function Sources({ data }: { data: Evaluation }) {
  const t = data.totals;
  const scored = data.passes.filter((p) => p.scored);
  const elapsed = scored.map((p) => p.elapsed_ms);
  const costs = scored.map((p) => p.cost_usd);
  const agreement = Object.entries(t.agreement);
  // An evaluation made with no recordings has no first run to date it by; runs recorded on several days name the first
  // and the last
  const firstDay = t.recorded_from ? day.format(new Date(t.recorded_from)) : '';
  const lastDay = t.recorded_to ? day.format(new Date(t.recorded_to)) : firstDay;
  const days = firstDay === lastDay ? firstDay : `${firstDay} to ${lastDay}`;
  const source = t.recorded_from
    ? `Every figure here comes from the recorded live runs of ${days}: ${formatInt(t.runs)} runs of ${andList(t.models)}, started between ${formatUtc(t.recorded_from)} and ${formatUtc(t.recorded_to)}, computed from the recordings by scripts/evaluate.py with no model calls.`
    : 'There are no recorded live runs to evaluate yet: scripts/evaluate.py found none.';
  return (
    <TechDetail kind="explain" label="Where these figures come from">
      <Stack gap="sm">
        <Text size="sm">{source}</Text>
        <Text size="sm">
          A pass is one board decision on one case: the three specialists in parallel (conformance, encounter,
          impact), then the coordinator, who writes the plan. A case planned again after a change has a pass
          per plan. A specialist decides from its own view only, so the action it proposes is what that view
          alone would choose, not a verdict on the case; its confidence is in that answer. Shutter stores and
          shows the confidence, and no rule in the core or the gate reads it.
        </Text>
        <KeyValueList
          rows={[
            [
              'The board against the expected outcome',
              `${t.board_matches} of ${t.scored_passes} scored passes (${t.cases} cases in ${t.scenarios} scenarios; ${t.passes} passes, ${t.passes - t.scored_passes} not scored)`,
            ],
            ['Agreement', andList(agreement.map(([how, n]) => `${how} in ${n}`)) + ` of ${t.passes} passes`],
            [
              'Each specialist alone',
              `${andList(SPECIALISTS.map((s) => `${s} in ${t.specialist_matches[s] ?? 0}`))} of ${t.scored_passes} scored passes gave the expected outcome from its own view`,
            ],
            [
              'Confidence',
              andList(
                Object.entries(t.confidence).map(
                  ([which, c]) =>
                    `${which === 'matched' ? 'the findings with the expected outcome' : 'those another view outweighed'}: ${confidenceGroup(c)}`,
                ),
              ),
            ],
            [
              'Tokens and cost',
              `${formatInt(t.prompt_tokens)} uncached input, ${formatInt(t.cache_read_tokens)} cache read, ${formatInt(t.cache_write_tokens)} cache written and ${formatInt(t.completion_tokens)} output tokens over ${formatInt(t.runs)} runs: ${formatUsd(t.cost_usd)} at list prices`,
            ],
            [
              'Per pass',
              scored.length
                ? `${formatUsd(Math.min(...costs))} to ${formatUsd(Math.max(...costs))}, and ${formatDuration(Math.min(...elapsed))} to ${formatDuration(Math.max(...elapsed))} from the first specialist's start to the plan; ${formatDuration(t.agent_ms)} of agent time in all`
                : 'No scored passes',
            ],
          ]}
        />
      </Stack>
    </TechDetail>
  );
}

/**
 * Why a board: who proposed the expected action of the scored passes (the board, then each specialist alone, on one
 * base), and which of rules alone's misses the gate stops by itself and which only the board catches.
 */
function WhyABoard({
  proof,
  caseOf,
}: {
  proof: Proof;
  caseOf: (scenario: string, mode: string) => CaseSummary | undefined;
}) {
  const b = proof.board;
  const sp = proof.specialists;
  const misses = proof.rulesMisses;
  const base = b?.scored ?? 0;
  const bar = (code: string, value: number) => ({
    label: MEMBERS[code].name,
    value,
    hue: MEMBERS[code].hue,
    hint: `${MEMBERS[code].name}: ${value} of ${base} scored passes`,
  });
  const ids = (list: string[]) =>
    list.map((id, i) => (
      <span key={id}>
        {i === 0 ? '' : i === list.length - 1 ? ' and ' : ', '}
        <CaseId id={id} c={caseOf(id, 'rules')} />
      </span>
    ));
  return (
    <Section id="why-a-board" title="Why a board">
      {b && sp && base ? (
        <ComparisonBars
          bars={[
            bar('board', b.matched),
            bar('impact', sp.impact),
            bar('encounter', sp.encounter),
            bar('conformance', sp.conformance),
          ]}
          of={base}
          caption={`Who proposed the expected action, of ${base} scored passes`}
        />
      ) : null}
      <Text size="sm">
        Each specialist agent answers from its own view only; the coordinator agent weighs all three.
      </Text>
      {misses && (misses.stopped.length || misses.wrote.length) ? (
        <Text size="sm">
          {misses.stopped.length ? <>The gate alone catches {ids(misses.stopped)}. </> : null}
          {misses.wrote.length ? <>Only the board catches {ids(misses.wrote)}.</> : null}
        </Text>
      ) : null}
    </Section>
  );
}

/** The per-scenario table's filters: Show, who the entry says decides, who was outweighed, the order, and the count. */
function Filters({
  filters,
  total,
  shown,
  set,
}: {
  filters: PassFilters;
  total: number;
  shown: number;
  set: (patch: Partial<Record<keyof PassFilters, string | null>>) => void;
}) {
  const id = useId();
  const standard = ['all', 'rules-differs', 'not-unanimous'];
  return (
    <Group gap="sm" align="flex-end" wrap="wrap" justify="space-between">
      <Group gap="xs" wrap="wrap" align="center">
        <Text size="sm" fw={600} id={id}>
          Show
        </Text>
        <Chip.Group
          multiple={false}
          value={filters.show}
          onChange={(v) => set({ show: v === 'all' ? null : (v as string) })}
        >
          <Group gap={6} wrap="wrap" role="group" aria-labelledby={id}>
            <Chip value="all" size="sm">
              {`All ${total}`}
            </Chip>
            <Chip value="rules-differs" size="sm">
              {SHOW_LABELS['rules-differs']}
            </Chip>
            <Chip value="not-unanimous" size="sm">
              {SHOW_LABELS['not-unanimous']}
            </Chip>
            {/* A filter a mark or an agreement row set shows here too, so the table says what it holds */}
            {standard.includes(filters.show) ? null : (
              <Chip value={filters.show} size="sm">
                {SHOW_LABELS[filters.show]}
              </Chip>
            )}
          </Group>
        </Chip.Group>
      </Group>
      <Group gap="sm" align="flex-end" wrap="wrap">
        <NativeSelect
          size="xs"
          label="Entry decides"
          value={filters.decides}
          onChange={(e) => set({ decides: e.currentTarget.value || null })}
          data={[
            { value: '', label: 'Any' },
            { value: 'policy', label: 'Policy' },
            { value: 'board', label: 'Board' },
            { value: 'person', label: 'Person' },
          ]}
        />
        <NativeSelect
          size="xs"
          label="Outweighed"
          value={filters.outweighed}
          onChange={(e) => set({ outweighed: e.currentTarget.value || null })}
          data={[
            { value: '', label: 'Any' },
            ...SPECIALISTS.map((s) => ({ value: s, label: MEMBERS[s].name })),
          ]}
        />
        <NativeSelect
          size="xs"
          label="Sort"
          value={filters.sort}
          onChange={(e) => set({ sort: e.currentTarget.value === 'scenario' ? null : e.currentTarget.value })}
          data={[
            { value: 'scenario', label: 'Scenario' },
            { value: 'cost', label: 'Cost, highest first' },
            { value: 'elapsed', label: 'Time, longest first' },
          ]}
        />
        <Text size="sm" aria-live="polite" aria-atomic="true" pb={4}>
          {`${plural(shown, 'pass', 'passes')} shown`}
        </Text>
      </Group>
    </Group>
  );
}

/** A specialist's column header: its identity dot (decoration) and its name. */
function MemberHeader({ code }: { code: Specialist }) {
  return (
    <Group gap={6} wrap="nowrap" component="span">
      <span
        className="identity-dot"
        style={{ ['--mark-hue' as string]: hueVar(MEMBERS[code].hue) }}
        aria-hidden
      />
      {MEMBERS[code].name}
    </Group>
  );
}

/**
 * The passes one row each, in 8 columns that fit a laptop: the pass (it stays in view when a narrow window scrolls the
 * table), what was expected, each specialist's view, the plan (its action, entry and agreement), how it ended played
 * end to end, and its cost and time. On a phone each pass is a compact card.
 */
function PassesTable({
  data,
  passes,
  filters,
  set,
}: {
  data: Evaluation;
  passes: EvaluationPass[];
  filters: PassFilters;
  set: (patch: Partial<Record<keyof PassFilters, string | null>>) => void;
}) {
  const t = data.totals;
  const technical = useTechnical();
  // Only the first "outweighed" on the page carries its definition
  const first = passes.find((p) => outweighedIn(p).length);
  const firstKey = first ? `${passKey(first)}/${outweighedIn(first)[0]}` : '';
  // Two passes the document names alike (S23a's two encounters) are told apart by their encounter
  const named = new Map<string, number>();
  for (const p of data.passes) named.set(passName(p), (named.get(passName(p)) ?? 0) + 1);
  return (
    <Card
      padding="md"
      component="section"
      aria-labelledby="passes-title"
      id="passes"
      className="eval-passes-card sticky-first-col"
      data-tour="evaluation-table"
    >
      <Box mb="sm">
        <Title order={2} id="passes-title" tabIndex={-1}>
          Per scenario
        </Title>
        <Text c="dimmed" maw="68ch" mb="sm">
          One row per pass: each agent&apos;s view, the plan, and how it ended.
        </Text>
        <Stack gap="xs">
          <Filters filters={filters} total={data.passes.length} shown={passes.length} set={set} />
          <TechDetail kind="explain" label="How to read this table">
            <Text size="sm">
              Each specialist&apos;s proposed action and its own confidence in it (the percentage); the
              plan&apos;s action, the catalogue entry it cites with who that entry says decides (policy: the
              catalogue alone may settle it in site-policy mode; board: it needs the board&apos;s judgement;
              person: only a person may act), and the dots of the specialists that proposed it; how the
              scenario ended when played end to end by the board and by rules alone; and the cost and time of
              the pass. In a scored pass, &quot;outweighed&quot; marks a view the plan set aside for another,
              and &quot;Not as expected&quot; a plan that is not the expected outcome.
            </Text>
          </TechDetail>
        </Stack>
      </Box>
      <Table.ScrollContainer minWidth={940} type="native" className="stack-scroll eval-passes-scroll">
        <StackTable verticalSpacing="xs" className="stack-table stack-cards eval-passes">
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th aria-sort={filters.sort === 'scenario' ? 'ascending' : undefined}>
                Pass
              </StackTable.Th>
              <StackTable.Th>Expected</StackTable.Th>
              {SPECIALISTS.map((s) => (
                <StackTable.Th key={s}>
                  <MemberHeader code={s} />
                </StackTable.Th>
              ))}
              <StackTable.Th>Plan</StackTable.Th>
              <StackTable.Th>Played</StackTable.Th>
              <StackTable.Th aria-sort={filters.sort === 'scenario' ? undefined : 'descending'}>
                Cost · time
              </StackTable.Th>
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {passes.map((p) => {
              const outweighed = outweighedIn(p);
              return (
                <StackTable.Tr key={passKey(p)} className="tone-row" data-tone={rowTone(p)}>
                  <StackTable.Td>
                    {/* A short name stays on one line; an incident's or a receiver's may wrap, so the column stays narrow */}
                    <Text
                      size="sm"
                      fw={600}
                      style={p.incident || p.receiver ? undefined : { whiteSpace: 'nowrap' }}
                    >
                      {passName(p)}
                    </Text>
                    <Text size="xs" c="dimmed">
                      {p.title}
                    </Text>
                    {(named.get(passName(p)) ?? 0) > 1 || technical ? (
                      <CodeChip fz="xs">{p.encounter}</CodeChip>
                    ) : null}
                  </StackTable.Td>
                  <StackTable.Td data-label="Expected">
                    <Text size="sm">{expected(p)}</Text>
                  </StackTable.Td>
                  {SPECIALISTS.map((s) => (
                    <StackTable.Td key={s} data-label={MEMBERS[s].name}>
                      <MemberCell
                        m={p.members[s]}
                        outweighed={outweighed.includes(s)}
                        term={`${passKey(p)}/${s}` === firstKey}
                      />
                    </StackTable.Td>
                  ))}
                  <StackTable.Td data-label="Plan">
                    <PlanCell p={p} />
                  </StackTable.Td>
                  <StackTable.Td data-label="Played" className="wrap-badges">
                    <PlayedCell p={p} />
                  </StackTable.Td>
                  <StackTable.Td data-label="Cost · time">
                    <Text size="sm">
                      <span data-label="Cost and tokens" style={{ whiteSpace: 'nowrap' }}>
                        {formatUsd(p.cost_usd)}
                      </span>
                      {' · '}
                      <span data-label="Elapsed" style={{ whiteSpace: 'nowrap' }}>
                        {formatDuration(p.elapsed_ms)}
                      </span>
                    </Text>
                    {technical ? (
                      <Text size="xs" c="dimmed">
                        {tokens(p)}
                      </Text>
                    ) : null}
                  </StackTable.Td>
                </StackTable.Tr>
              );
            })}
            <StackTable.Tr>
              <StackTable.Th>Total</StackTable.Th>
              <StackTable.Td colSpan={6}>
                <Text size="sm">{`${t.passes} passes, ${t.runs} runs`}</Text>
              </StackTable.Td>
              <StackTable.Td data-label="Cost · time">
                <Text size="sm">
                  {formatUsd(t.cost_usd)}
                  {' · '}
                  <span style={{ whiteSpace: 'nowrap' }}>{formatDuration(t.agent_ms)}</span> of agent time
                </Text>
                <Text
                  size="xs"
                  c="dimmed"
                >{`${formatInt(t.prompt_tokens)} in · ${formatInt(t.cache_read_tokens)} cached · ${formatInt(t.cache_write_tokens)} cache written · ${formatInt(t.completion_tokens)} out`}</Text>
              </StackTable.Td>
            </StackTable.Tr>
          </StackTable.Tbody>
        </StackTable>
      </Table.ScrollContainer>
      {passes.length ? null : (
        <Text size="sm" mt="xs">
          No pass matches these filters.{' '}
          <Anchor
            component="button"
            type="button"
            size="sm"
            onClick={() => set({ show: null, decides: null, outweighed: null })}
          >
            Show every pass
          </Anchor>
        </Text>
      )}
    </Card>
  );
}

/** "More about repeat runs": the disclosure's name from an item's title. */
const moreAbout = (title: string) => {
  const words = title.replace(/[.:]\s*$/, '');
  return `More about ${words.charAt(0).toLowerCase()}${words.slice(1)}`;
};

/** The page; a test may pass other documents of the same shapes. */
export default function EvaluationPage({
  data = EVALUATION,
  refusals = BOUNDARY,
}: {
  data?: Evaluation;
  refusals?: BoundaryChecks;
}) {
  const proof = useMemo(() => proofFrom(data as unknown as ProofSource), [data]);
  const [params, setParams] = useSearchParams();
  const filters = readFilters(params);
  const reduced = usePrefersReducedMotion();
  const caseOf = useScenarioCases();
  const shown = filterPasses(data.passes, filters);
  const range = dayRange(proof.recordedFrom, proof.recordedTo);

  const set = (patch: Partial<Record<keyof PassFilters, string | null>>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(patch)) {
      if (v) next.set(k, v);
      else next.delete(k);
    }
    setParams(next, { replace: true });
  };
  // A mark or an agreement row turns its filter on and brings the table into view, or turns it off where it is
  const toggle = (show: string) => {
    if (filters.show === show) return set({ show: null });
    set({ show });
    document
      .getElementById('passes')
      ?.scrollIntoView?.({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
    document.getElementById('passes-title')?.focus({ preventScroll: true });
  };

  return (
    <>
      <PageHeader
        title="Evaluation"
        icon={IconChartBar}
        hue="teal"
        lead={`How the board decides, measured on runs recorded with the real agents${range ? `, ${range}` : ''}.`}
        details="How the board decides: the action it proposed against each scenario's expected outcome and against rules alone, every member's own view and confidence, how far they agreed, and what each pass cost in tokens, money and time."
      />
      <Stack gap="md">
        <Headline data={data} proof={proof} filters={filters} toggle={toggle} caseOf={caseOf} />
        <WhyABoard proof={proof} caseOf={caseOf} />
        <PassesTable data={data} passes={shown} filters={filters} set={set} />

        <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md" style={{ alignItems: 'start' }}>
          <Section id="not-measured" title="Not yet measured">
            <List size="sm" spacing="sm">
              {NOT_YET.map((item) => {
                const { first, rest } = firstSentence(item.text);
                return (
                  <List.Item key={item.title || item.text}>
                    {item.title ? (
                      <Text span size="sm" fw={600}>
                        {item.title}{' '}
                      </Text>
                    ) : null}
                    <Text span size="sm">
                      {first}
                    </Text>
                    {rest ? (
                      <TechDetail kind="explain" label={item.title ? moreAbout(item.title) : 'More about it'}>
                        <Text size="sm">{rest}</Text>
                      </TechDetail>
                    ) : null}
                  </List.Item>
                );
              })}
            </List>
          </Section>
          <Section id="without-board" title="Scenarios with no board recordings">
            <List size="sm" spacing="sm">
              {data.without_board.map((s) => (
                <List.Item key={s.scenario}>
                  <Text span size="sm" fw={600}>
                    {s.scenario} {s.title}:{' '}
                  </Text>
                  <Text span size="sm">
                    {s.why}.
                  </Text>
                </List.Item>
              ))}
            </List>
          </Section>
        </SimpleGrid>

        <Section
          id="boundary"
          title="What the boundary refuses"
          note={`What ${refusals.script} tries over HTTP against the approval boundary, and the answer each attempt must get. It runs in ${refusals.runs}, and on any instance of your own (it plays the scenarios it names, so not on one someone else is using).`}
        >
          <Table.ScrollContainer minWidth={800} className="stack-scroll">
            <StackTable verticalSpacing="xs" className="stack-table">
              <StackTable.Thead>
                <StackTable.Tr>
                  <StackTable.Th>Attempt</StackTable.Th>
                  <StackTable.Th>Scenario</StackTable.Th>
                  <StackTable.Th>Answer</StackTable.Th>
                  <StackTable.Th>What it proves</StackTable.Th>
                </StackTable.Tr>
              </StackTable.Thead>
              <StackTable.Tbody>
                {refusals.checks.map((c) => (
                  <StackTable.Tr key={c.id}>
                    <StackTable.Td>
                      <Text fw={600}>{c.title}</Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Scenario">
                      <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                        {c.scenario}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Answer">
                      <CodeChip>{c.answer}</CodeChip>
                    </StackTable.Td>
                    <StackTable.Td data-label="What it proves">
                      <Text size="sm">{c.proves}</Text>
                    </StackTable.Td>
                  </StackTable.Tr>
                ))}
              </StackTable.Tbody>
            </StackTable>
          </Table.ScrollContainer>
        </Section>

        <Stack gap={4}>
          <TechDetail kind="explain" label="Where these figures come from: files and prices">
            <Stack gap="sm">
              <Text size="sm">
                The files of the repository the evaluation reads, and the list prices per million tokens it
                applies to each run&apos;s tokens, as the Settings page does.
              </Text>
              <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
                <KeyValueList
                  rows={Object.entries(data.sources).map(([key, value]) => [humanize(key), value])}
                />
                <Table.ScrollContainer minWidth={440}>
                  <Table>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th>Model</Table.Th>
                        <Table.Th>Input</Table.Th>
                        <Table.Th>Output</Table.Th>
                        <Table.Th>Cache read</Table.Th>
                        <Table.Th>Cache write</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {Object.entries(data.prices_per_million).map(([model, price]) => (
                        <Table.Tr key={model}>
                          <Table.Td>
                            <Text size="sm" className="mono-wrap">
                              {model}
                            </Text>
                          </Table.Td>
                          <Table.Td>{formatUsd(price.input)}</Table.Td>
                          <Table.Td>{formatUsd(price.output)}</Table.Td>
                          <Table.Td>{formatUsd(price.cache_read)}</Table.Td>
                          <Table.Td>{formatUsd(price.cache_write)}</Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                </Table.ScrollContainer>
              </SimpleGrid>
            </Stack>
          </TechDetail>
          <ApiSource endpoint="docs/readme/evaluation.json" data={data} />
        </Stack>
      </Stack>
    </>
  );
}
