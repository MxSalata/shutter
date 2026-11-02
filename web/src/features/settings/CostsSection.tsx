import { Anchor, SimpleGrid, Stack, Text } from '@mantine/core';
import { Link } from 'react-router';
import type { Budget, Costs, Settings } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { TechDetail } from '@/components/TechDetail';
import { TRIAL } from '@/env/mode';
import { budgetText, resetsHourly } from '@/lib/budget';
import { formatInt, formatUsd } from '@/lib/format';
import { costsSentences, runWord, sameCases } from './settingsText';

/** The model budget in words (CONTRACTS 9): the day's cap, or on the public demo the cap per reset, and the user's share. */
function BudgetWords({ b, s }: { b: Budget; s: Settings | undefined }) {
  const words = budgetText(b, { resetsHourly: resetsHourly(s) });
  if (!words) return null;
  return (
    <Stack gap={2} data-testid="budget">
      <Text size="sm">{words.today}</Text>
      {words.share ? <Text size="sm">{words.share}</Text> : null}
    </Stack>
  );
}

function ByModel({ rows }: { rows: Costs['byModel'] }) {
  return (
    <Stack gap={4}>
      <Text size="sm" fw={600}>
        By model
      </Text>
      {rows.length === 0 ? (
        <Text size="sm" c="dimmed">
          No agent runs recorded.
        </Text>
      ) : (
        <StackTable aria-label="Costs by model" className="stack-table">
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th>Model</StackTable.Th>
              <StackTable.Th ta="right">Runs</StackTable.Th>
              <StackTable.Th ta="right">Tokens in / out</StackTable.Th>
              <StackTable.Th ta="right">Cost</StackTable.Th>
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {rows.map((m) => (
              <StackTable.Tr key={`${m.model}|${m.mode ?? ''}`}>
                <StackTable.Td data-label="Model">
                  <CodeChip>{m.model}</CodeChip>
                  {m.mode ? (
                    <Text span size="xs" c="dimmed">
                      {' '}
                      · {runWord(m.mode)}
                    </Text>
                  ) : null}
                </StackTable.Td>
                <StackTable.Td data-label="Runs" ta="right" className="tabular">
                  {m.runs}
                </StackTable.Td>
                <StackTable.Td data-label="Tokens in / out" ta="right" className="tabular">
                  {formatInt(m.promptTokens)} / {formatInt(m.completionTokens)}
                </StackTable.Td>
                <StackTable.Td data-label="Cost" ta="right" className="tabular">
                  {formatUsd(m.costUsd)}
                </StackTable.Td>
              </StackTable.Tr>
            ))}
          </StackTable.Tbody>
        </StackTable>
      )}
    </Stack>
  );
}

function ByReview({ rows }: { rows: NonNullable<Costs['byReview']> }) {
  return (
    <Stack gap={4}>
      <Text size="sm" fw={600}>
        By production review
      </Text>
      <StackTable aria-label="Costs by production review" className="stack-table">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Review</StackTable.Th>
            <StackTable.Th>Production</StackTable.Th>
            <StackTable.Th>Model</StackTable.Th>
            <StackTable.Th ta="right">Cost</StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {rows.map((r) => (
            <StackTable.Tr key={r.reviewId}>
              <StackTable.Td data-label="Review">
                <Anchor component={Link} to={`/reviews/${encodeURIComponent(r.reviewId)}`} size="sm">
                  {r.reviewId}
                </Anchor>
              </StackTable.Td>
              <StackTable.Td data-label="Production">{r.production}</StackTable.Td>
              <StackTable.Td data-label="Model">
                {r.model ? <CodeChip>{r.model}</CodeChip> : null}
                {r.mode ? (
                  <Text span size="xs" c="dimmed">
                    {r.model ? ' · ' : ''}
                    {runWord(r.mode)}
                  </Text>
                ) : r.model ? null : (
                  <Text span size="sm" c="dimmed">
                    none
                  </Text>
                )}
              </StackTable.Td>
              <StackTable.Td data-label="Cost" ta="right" className="tabular">
                {formatUsd(r.costUsd)}
              </StackTable.Td>
            </StackTable.Tr>
          ))}
        </StackTable.Tbody>
      </StackTable>
    </Stack>
  );
}

function CaseTable({ rows }: { rows: Costs['byCase'] }) {
  return (
    <StackTable aria-label="Costs by case" className="stack-table">
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Case</StackTable.Th>
          <StackTable.Th ta="right">Runs</StackTable.Th>
          <StackTable.Th ta="right">Cost</StackTable.Th>
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {rows.map((c) => (
          <StackTable.Tr key={c.caseId}>
            <StackTable.Td data-label="Case">{c.caseId}</StackTable.Td>
            <StackTable.Td data-label="Runs" ta="right" className="tabular">
              {c.replayedRuns && c.replayedRuns === c.runs
                ? `${c.runs} replayed`
                : `${c.runs}${c.replayedRuns ? ` (${c.replayedRuns} replayed)` : ''}`}
            </StackTable.Td>
            <StackTable.Td data-label="Cost" ta="right" className="tabular">
              {formatUsd(c.costUsd)}
            </StackTable.Td>
          </StackTable.Tr>
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
}

/** The cases' costs: one line behind a disclosure when every case is the same, the table itself when they differ. */
function ByCase({ rows }: { rows: Costs['byCase'] }) {
  if (rows.length === 0)
    return (
      <Text size="sm" c="dimmed">
        No cases with agent runs.
      </Text>
    );
  const same = sameCases(rows);
  if (same)
    return (
      <TechDetail label={same} kind="data">
        <CaseTable rows={rows} />
      </TechDetail>
    );
  return (
    <Stack gap={4}>
      <Text size="sm" fw={600}>
        By case
      </Text>
      <CaseTable rows={rows} />
    </Stack>
  );
}

/**
 * The Costs section: what the budget allows and has spent, what was spent in a sentence, then the cost by model and by
 * production review side by side, and the cases behind one line when they are alike.
 */
export function CostsSection({
  costs,
  settings,
}: {
  costs: { data?: Costs; isError: boolean; error: unknown };
  settings: Settings | undefined;
}) {
  const c = costs.data;
  const totals = c?.totals;
  const sentences = totals?.spentUsd !== undefined ? costsSentences(totals, TRIAL) : null;
  return (
    <Section id="settings-costs" title="Costs" tour="settings-costs">
      {settings?.budget ? <BudgetWords b={settings.budget} s={settings} /> : null}
      {costs.isError ? <ErrorAlert error={costs.error} title="The costs could not be read" /> : null}
      {sentences ? (
        <Text size="sm">
          <Text span fw={700}>
            {sentences.spent}
          </Text>
          {sentences.rest}
        </Text>
      ) : null}
      {c ? (
        <>
          <SimpleGrid cols={{ base: 1, lg: c.byReview?.length ? 2 : 1 }} spacing="md">
            <ByModel rows={c.byModel} />
            {c.byReview?.length ? <ByReview rows={c.byReview} /> : null}
          </SimpleGrid>
          <ByCase rows={c.byCase} />
        </>
      ) : null}
    </Section>
  );
}
