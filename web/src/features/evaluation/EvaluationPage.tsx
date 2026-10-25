import { Anchor, Card, List, SimpleGrid, Stack, Table, Text, Title } from '@mantine/core';
import evaluation from '../../../../docs/readme/evaluation.json';
import evaluationText from '../../../../docs/readme/evaluation.md?raw';
import boundary from '../../../../docs/readme/boundary.json';
import { PageHeader } from '@/components/PageHeader';
import { KeyValueList } from '@/components/KeyValueList';
import { DispositionBadge } from '@/components/StateBadge';
import { StackTable } from '@/components/StackTable';
import { formatDuration, formatInt, formatUsd, formatUtc, humanize } from '@/lib/format';
import {
  notYetMeasured,
  passName,
  played,
  playedLine,
  SPECIALISTS,
  type BoundaryChecks,
  type Evaluation,
  type EvaluationConfidence,
  type EvaluationMember,
  type EvaluationPass,
} from './evaluation';

/**
 * How the board decides, from docs/readme/evaluation.json: the document scripts/evaluate.py writes from the recorded
 * live runs, read here at build time (never copied by hand), with the "Not yet measured" list from evaluation.md, and
 * what the boundary refuses from docs/readme/boundary.json, which tests/e2e/boundary_check.py writes.
 */
const EVALUATION = evaluation as unknown as Evaluation;
const NOT_YET = notYetMeasured(evaluationText);
const BOUNDARY: BoundaryChecks = boundary;
const day = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

/** The list's "a, b and c" from a few parts. */
const andList = (parts: string[]) => parts.join(', ').replace(/, ([^,]*)$/, ' and $1');

/**
 * What evaluation.md marks in a member's cell: nothing in a pass that is not scored; in a scored one, a specialist
 * whose disposition is not the plan's was outweighed, and a plan that is not the expected outcome differs.
 */
function memberNote(m: EvaluationMember, p: EvaluationPass, plan: boolean): string {
  if (!p.scored) return '';
  if (plan) return m.matches_expected === false ? 'differs' : '';
  return m.disposition !== p.board_disposition ? 'outweighed' : '';
}

/** A member's disposition and, for a specialist, its confidence, with its note. */
function MemberCell({ m, p, plan }: { m: EvaluationMember | undefined; p: EvaluationPass; plan: boolean }) {
  if (!m) return <Text size="sm">-</Text>;
  const confidence =
    m.confidence !== null && m.confidence !== undefined
      ? `confidence ${Math.round(m.confidence * 100)}%`
      : '';
  const note = memberNote(m, p, plan);
  return (
    <Stack gap={2}>
      <DispositionBadge disposition={m.disposition} />
      {confidence || note ? (
        <Text size="xs" c="dimmed" style={{ whiteSpace: 'nowrap' }}>
          {[confidence, note].filter(Boolean).join(' · ')}
        </Text>
      ) : null}
    </Stack>
  );
}

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

/**
 * The headline result with its scope and its limits beside it, never further down the page: what the figure counts,
 * which set it was measured on, and what is planned but not yet reported.
 */
function Headline({ data }: { data: Evaluation }) {
  const t = data.totals;
  const rules = played(data, 'rules');
  // The board played end to end on the same passes as rules alone, so the two figures count one set
  const board = played(data, 'board_live', 'rules');
  return (
    <Card padding="md" component="section" aria-labelledby="headline-title" data-tour="evaluation-headline">
      <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
        <Stack gap={2}>
          <Title order={2} fz="sm" c="dimmed" fw={600} id="headline-title">
            The board against the expected outcome
          </Title>
          <Text fz={28} fw={650} className="tabular">
            {t.scored_passes ? `${t.board_matches} of ${t.scored_passes}` : 'None scored'}
          </Text>
          <Text size="sm">scored passes proposed the scenario's expected action</Text>
        </Stack>
        <Stack gap={2}>
          <Text size="sm" c="dimmed" fw={600}>
            Rules alone, the baseline
          </Text>
          <Text fz={28} fw={650} className="tabular">
            {rules.of ? `${rules.matches} of ${rules.of}` : 'Not played'}
          </Text>
          <Text size="sm">
            {rules.of
              ? `scored passes played end to end with rules alone, no agents, ended as expected${board.of ? `; played the same way, the board ended as expected in ${board.matches} of the same ${board.of}` : ''}`
              : 'no scored pass was played with rules alone'}
          </Text>
        </Stack>
        <Stack gap={2}>
          <Text size="sm" fw={600}>
            Scope
          </Text>
          <Text size="sm">
            {`${t.scenarios} scenarios, ${t.cases} cases and ${t.passes} passes (${t.passes - t.scored_passes} not scored), from the recorded set: one recording per member, on the scenarios the catalogue was written alongside.`}
          </Text>
        </Stack>
        <Stack gap={2}>
          <Text size="sm" fw={600}>
            Limits
          </Text>
          <Text size="sm">
            Planned, not yet reported: repeat runs of each scenario, held-out variants, and a comparison with
            a single investigator. A match shows agreement with each scenario's expected outcome, on scenarios
            the catalogue was written alongside; it is not evidence of general reliability.{' '}
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
      </SimpleGrid>
    </Card>
  );
}

/** The page; a test may pass other documents of the same shapes. */
export default function EvaluationPage({
  data = EVALUATION,
  refusals = BOUNDARY,
}: {
  data?: Evaluation;
  refusals?: BoundaryChecks;
}) {
  const t = data.totals;
  const scored = data.passes.filter((p) => p.scored);
  const elapsed = scored.map((p) => p.elapsed_ms);
  const costs = scored.map((p) => p.cost_usd);
  const agreement = Object.entries(t.agreement);
  // An evaluation made with no recordings has no first run to date it by
  const source = t.recorded_from
    ? `Every figure here comes from the recorded live runs of ${day.format(new Date(t.recorded_from))}: ${formatInt(t.runs)} runs of ${andList(t.models)}, started between ${formatUtc(t.recorded_from)} and ${formatUtc(t.recorded_to)}, computed from the recordings by scripts/evaluate.py with no model calls.`
    : 'There are no recorded live runs to evaluate yet: scripts/evaluate.py found none.';
  return (
    <>
      <PageHeader
        title="Evaluation"
        subtitle="How the board decides: the action it proposed against each scenario's expected outcome and against rules alone, every member's own view and confidence, how far they agreed, and what each pass cost in tokens, money and time."
      />
      <Stack gap="md">
        <Headline data={data} />
        <Card padding="md">
          <Stack gap="sm">
            <Text size="sm" fw={600}>
              {`${source} Nothing on this page was measured on this instance.`}
            </Text>
            <Text size="sm" c="dimmed">
              A pass is one board decision on one case: the three specialists in parallel (conformance,
              encounter, impact), then the coordinator, who writes the plan. A case planned again after a
              change has a pass per plan. A specialist decides from its own view only, so the action it
              proposes is what that view alone would choose, not a verdict on the case; its confidence is in
              that answer. Shutter stores and shows the confidence, and no rule in the core or the gate reads
              it.
            </Text>
            <KeyValueList
              rows={[
                [
                  'The board against the expected outcome',
                  `${t.board_matches} of ${t.scored_passes} scored passes (${t.cases} cases in ${t.scenarios} scenarios; ${t.passes} passes, ${t.passes - t.scored_passes} not scored)`,
                ],
                [
                  'Agreement',
                  andList(agreement.map(([how, n]) => `${how} in ${n}`)) + ` of ${t.passes} passes`,
                ],
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
        </Card>

        <Card padding="md" component="section" aria-labelledby="passes-title">
          <Title order={2} fz="lg" id="passes-title" mb={4}>
            Per scenario
          </Title>
          <Text size="sm" c="dimmed" mb="sm">
            Each member's proposed action and confidence; the plan's action, with how the scenario ended when
            played end to end by the board and by rules alone; the catalogue entry the plan cites with who it
            says decides (policy: the catalogue alone may settle it in site-policy mode; board: it needs the
            board's judgement; person: only a person may act), the agreement, and the tokens, cost and time of
            the pass. In a scored pass, "outweighed" marks a view the plan set aside for another, and
            "differs" a plan that is not the expected outcome.
          </Text>
          {/* On a phone each pass is a card, every column under its name */}
          <Table.ScrollContainer minWidth={960} className="stack-scroll">
            <StackTable verticalSpacing="xs" className="stack-table">
              <StackTable.Thead>
                <StackTable.Tr>
                  <StackTable.Th>Pass</StackTable.Th>
                  <StackTable.Th>Expected</StackTable.Th>
                  <StackTable.Th>Conformance</StackTable.Th>
                  <StackTable.Th>Encounter</StackTable.Th>
                  <StackTable.Th>Impact</StackTable.Th>
                  <StackTable.Th>Plan</StackTable.Th>
                  <StackTable.Th>Entry</StackTable.Th>
                  <StackTable.Th>Agreement</StackTable.Th>
                  <StackTable.Th>Cost and tokens</StackTable.Th>
                  <StackTable.Th>Elapsed</StackTable.Th>
                </StackTable.Tr>
              </StackTable.Thead>
              <StackTable.Tbody>
                {data.passes.map((p) => (
                  <StackTable.Tr key={passName(p)}>
                    <StackTable.Td>
                      <Text size="sm" fw={600} style={{ whiteSpace: 'nowrap' }}>
                        {passName(p)}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {p.title}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Expected">
                      <Text size="sm">{expected(p)}</Text>
                    </StackTable.Td>
                    {SPECIALISTS.map((s) => (
                      <StackTable.Td key={s} data-label={humanize(s)}>
                        <MemberCell m={p.members[s]} p={p} plan={false} />
                      </StackTable.Td>
                    ))}
                    <StackTable.Td data-label="Plan">
                      <MemberCell m={p.members.coordinator} p={p} plan />
                      {playedLine(p) ? (
                        <Text size="xs" c="dimmed">
                          {playedLine(p)}
                        </Text>
                      ) : null}
                    </StackTable.Td>
                    <StackTable.Td data-label="Entry">
                      <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                        {p.catalogue_entry || '-'}
                        {p.entry_decides ? ` (${p.entry_decides})` : ''}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Agreement">
                      <Text size="sm">{p.agreement}</Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Cost and tokens">
                      <Text size="sm">{formatUsd(p.cost_usd)}</Text>
                      <Text size="xs" c="dimmed">
                        {tokens(p)}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Elapsed">
                      <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                        {formatDuration(p.elapsed_ms)}
                      </Text>
                    </StackTable.Td>
                  </StackTable.Tr>
                ))}
                <StackTable.Tr>
                  <StackTable.Th>Total</StackTable.Th>
                  <StackTable.Td colSpan={7}>
                    <Text size="sm">{`${t.passes} passes, ${t.runs} runs`}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Cost and tokens">
                    <Text size="sm">{formatUsd(t.cost_usd)}</Text>
                    <Text
                      size="xs"
                      c="dimmed"
                    >{`${formatInt(t.prompt_tokens)} in · ${formatInt(t.cache_read_tokens)} cached · ${formatInt(t.cache_write_tokens)} cache written · ${formatInt(t.completion_tokens)} out`}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Time">
                    <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                      {`${formatDuration(t.agent_ms)} of agent time`}
                    </Text>
                  </StackTable.Td>
                </StackTable.Tr>
              </StackTable.Tbody>
            </StackTable>
          </Table.ScrollContainer>
        </Card>

        <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
          <Card
            padding="md"
            component="section"
            aria-labelledby="not-measured-title"
            data-tour="evaluation-limits"
          >
            <Title order={2} fz="lg" id="not-measured-title" mb="sm" tabIndex={-1}>
              Not yet measured
            </Title>
            <List size="sm" spacing="sm">
              {NOT_YET.map((item) => (
                <List.Item key={item.title || item.text}>
                  {item.title ? (
                    <Text span size="sm" fw={600}>
                      {item.title}{' '}
                    </Text>
                  ) : null}
                  <Text span size="sm">
                    {item.text}
                  </Text>
                </List.Item>
              ))}
            </List>
          </Card>
          <Card padding="md" component="section" aria-labelledby="without-board-title">
            <Title order={2} fz="lg" id="without-board-title" mb="sm">
              Scenarios with no board recordings
            </Title>
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
          </Card>
        </SimpleGrid>

        <Card padding="md" component="section" aria-labelledby="boundary-title">
          <Title order={2} fz="lg" id="boundary-title" mb={4}>
            What the boundary refuses
          </Title>
          <Text size="sm" c="dimmed" mb="sm">
            {`What ${refusals.script} tries over HTTP against the approval boundary, and the answer each attempt must get. It runs in ${refusals.runs}, and on any instance of your own (it plays the scenarios it names, so not on one someone else is using).`}
          </Text>
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
                      <Text size="sm" fw={600}>
                        {c.title}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Scenario">
                      <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                        {c.scenario}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Answer">
                      <Text size="sm" className="mono-wrap">
                        {c.answer}
                      </Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="What it proves">
                      <Text size="sm">{c.proves}</Text>
                    </StackTable.Td>
                  </StackTable.Tr>
                ))}
              </StackTable.Tbody>
            </StackTable>
          </Table.ScrollContainer>
        </Card>

        <Card padding="md" component="section" aria-labelledby="sources-title">
          <Title order={2} fz="lg" id="sources-title" mb={4}>
            Where the figures come from
          </Title>
          <Text size="sm" c="dimmed" mb="sm">
            The files of the repository the evaluation reads, and the list prices per million tokens it
            applies to each run's tokens, as the Settings page does.
          </Text>
          <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
            <KeyValueList rows={Object.entries(data.sources).map(([key, value]) => [humanize(key), value])} />
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
          </SimpleGrid>
        </Card>
      </Stack>
    </>
  );
}
