import { Anchor, Badge, Card, Group, SimpleGrid, Stack, Table, Text, Title } from '@mantine/core';
import { Link } from 'react-router';
import { useCosts, useSettings } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { formatInt, formatUsd, humanize } from '@/lib/format';
import type { AgentItem, Settings } from '@/api/types';

function Flag({ children }: { children: React.ReactNode }) {
  return (
    <Badge color="teal" variant="light" style={{ textTransform: 'none' }}>
      {children}
    </Badge>
  );
}

/**
 * How the agents answer, by the mode they run in now; a replaying instance counts the replays it has run. Under the
 * API mimic (a test fixture) a live item is still live, but no model answers it.
 */
function answering(mode: string, replayed: number | undefined, mock = false): string {
  if (mode === 'replay')
    return `replaying recorded live runs${replayed ? ` (${formatInt(replayed)} ${replayed === 1 ? 'replay' : 'replays'} so far)` : ''}`;
  if (mode === 'live' && mock)
    return 'running live against the API mimic (tests/mock): no model is called and the runs cost nothing';
  if (mode === 'live') return 'running live on the configured model provider';
  if (mode === 'record') return 'running live and recording each run';
  return humanize(mode).toLowerCase();
}

/**
 * What the instance has, first: its agents and how they answer, then what is present. What it lacks follows in one
 * line, since a replaying instance needs none of it.
 */
function Configured({ s, replayed }: { s: Settings; replayed: number | undefined }) {
  const agents = s.agentItems.filter((a) => a.agentClass && a.enabled !== false);
  const modes = [...new Set(agents.map((a) => a.effectiveMode || a.mode || ''))];
  const how =
    modes.length === 1 ? answering(modes[0], replayed, !!s.mock) : 'in different modes, as the table shows';
  const missing = [
    !s.aiHubPresent && 'AI Hub',
    !s.liveRunnerPresent && 'the live runner',
    s.providerConfigured === false && 'a model provider',
  ].filter(Boolean) as string[];
  return (
    <Stack gap="xs">
      <Text fw={600}>
        {`${agents.length} ${s.aiHubPresent ? 'AI Hub ' : ''}${agents.length === 1 ? 'agent' : 'agents'}, ${how}`}
      </Text>
      <Group gap="sm" wrap="wrap">
        <Flag>Mode: {humanize(s.mode)}</Flag>
        {s.demo ? <Flag>Demo instance</Flag> : null}
        {s.mock ? <Flag>API mimic on{s.mockConfig ? ` (${s.mockConfig})` : ''}</Flag> : null}
        {s.aiHubPresent ? <Flag>AI Hub present</Flag> : null}
        {s.liveRunnerPresent ? <Flag>Live runner installed</Flag> : null}
        {s.providerConfigured ? <Flag>Model provider configured</Flag> : null}
        {s.scenario ? <Text size="sm">Last scenario: {s.scenario}</Text> : null}
        {s.resetAt ? (
          <Group gap={4}>
            <Text size="sm">Last reset</Text>
            <Timestamp iso={s.resetAt} />
          </Group>
        ) : null}
      </Group>
      {s.mock ? (
        <Text size="sm">
          No model answers while the mimic is on; the runs are labelled mock and cost nothing.
        </Text>
      ) : null}
      {missing.length ? (
        <Text size="sm">
          Not on this instance: {missing.join(', ').replace(/, ([^,]*)$/, ' and $1')}.
          {modes.length === 1 && modes[0] === 'replay'
            ? ' A replay needs none of them: the recorded runs answer.'
            : ''}
        </Text>
      ) : null}
    </Stack>
  );
}

type ItemColumn = {
  key: 'mode' | 'model' | 'providerConfig' | 'answeredBy' | 'maxIterations' | 'tokenBudget';
  label: string;
};
const ITEM_COLUMNS: ItemColumn[] = [
  { key: 'mode', label: 'Mode' },
  { key: 'model', label: 'Model' },
  { key: 'providerConfig', label: 'Provider' },
  { key: 'answeredBy', label: 'Answered by' },
  { key: 'maxIterations', label: 'Iterations' },
  { key: 'tokenBudget', label: 'Token budget' },
];

/** The agent items, with only the settings some item has: a replaying item has no model or limits. */
function AgentItemsTable({ items }: { items: AgentItem[] }) {
  const columns = ITEM_COLUMNS.filter((c) => items.some((a) => a[c.key] !== undefined && a[c.key] !== ''));
  const show = (c: ItemColumn, a: AgentItem) => {
    const v = a[c.key];
    if (v === undefined || v === '') return 'not set';
    if (c.key === 'mode')
      return a.effectiveMode && a.effectiveMode !== v
        ? `${humanize(String(v))} (${a.effectiveMode})`
        : humanize(String(v));
    if (c.key === 'tokenBudget') return formatInt(v);
    return String(v);
  };
  return (
    <Table.ScrollContainer minWidth={520}>
      <Table>
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Production item</Table.Th>
            {columns.map((c) => (
              <Table.Th key={c.key}>{c.label}</Table.Th>
            ))}
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {items.map((a) => (
            <Table.Tr key={a.name}>
              <Table.Td>
                <Text size="sm" fw={500}>
                  {a.name}
                  {a.enabled === false ? ' (disabled)' : ''}
                </Text>
                {a.agentClass ? (
                  <Text size="xs" c="dimmed">
                    {a.agentClass}
                  </Text>
                ) : null}
              </Table.Td>
              {columns.map((c) => (
                <Table.Td key={c.key}>
                  <Text size="sm" className={c.key === 'model' ? 'mono-wrap' : undefined}>
                    {show(c, a)}
                  </Text>
                </Table.Td>
              ))}
            </Table.Tr>
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}

export default function SettingsPage() {
  const settings = useSettings();
  const costs = useCosts();
  const s = settings.data;
  return (
    <>
      <PageHeader
        title="Settings and costs"
        subtitle="Read from the production and the store. Changes to the agent items are made in the production's settings."
      />
      <Stack gap="md">
        {settings.isPending ? <PageSkeleton label="Loading the settings…" /> : null}
        {settings.isError ? (
          <ErrorAlert
            error={settings.error}
            title="The settings could not be read"
            onRetry={() => void settings.refetch()}
          />
        ) : null}
        {s ? (
          <>
            <Card padding="md">
              <Stack gap="sm">
                <Configured s={s} replayed={costs.data?.totals?.replayedRuns} />
                <Text size="sm">
                  How well the board decides, from its recorded live runs: every member's disposition and
                  confidence per scenario, the agreement, the tokens, the cost and the time, and what is not
                  yet measured.{' '}
                  <Anchor component={Link} to="/evaluation" size="sm" underline="always">
                    Evaluation
                  </Anchor>
                </Text>
              </Stack>
            </Card>
            <Card padding="md">
              <Title order={2} fz="lg" mb={4}>
                Agent items
              </Title>
              <Text size="sm" c="dimmed" mb="sm">
                Each item runs its agent live, records a live run, or replays a recording; auto runs live when
                a model provider is configured and replays otherwise. A replay answers with the recorded run
                for a scenario's case. A case with no recording, such as one from an HL7 file of your own,
                takes the rules path instead: the gate alone decides, and a resend still waits for a person's
                approval.
              </Text>
              <AgentItemsTable items={s.agentItems} />
            </Card>
            <Card padding="md">
              <Title order={2} fz="lg" mb={4}>
                Prices used for costs
              </Title>
              <Text size="sm" c="dimmed" mb="sm">
                Per million tokens, as stored with their source and date; costs are computed from them, not
                billed amounts.
              </Text>
              <Table.ScrollContainer minWidth={720}>
                <Table>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Model</Table.Th>
                      <Table.Th>Input</Table.Th>
                      <Table.Th>Output</Table.Th>
                      <Table.Th>Cache read</Table.Th>
                      <Table.Th>Cache write</Table.Th>
                      <Table.Th>Source</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {s.prices.map((p) => (
                      <Table.Tr key={p.model}>
                        <Table.Td>
                          <Text size="sm" className="mono-wrap">
                            {p.model}
                          </Text>
                        </Table.Td>
                        <Table.Td>{formatUsd(p.inputPerMTok)}</Table.Td>
                        <Table.Td>{formatUsd(p.outputPerMTok)}</Table.Td>
                        <Table.Td>{formatUsd(p.cacheReadPerMTok)}</Table.Td>
                        <Table.Td>{formatUsd(p.cacheWritePerMTok)}</Table.Td>
                        <Table.Td>
                          <Text size="xs">
                            {p.source}
                            {p.asOf && !p.source.includes(p.asOf) ? ` (${p.asOf})` : ''}
                          </Text>
                        </Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            </Card>
          </>
        ) : null}
        <Card padding="md">
          <Title order={2} fz="lg" mb="sm">
            Costs
          </Title>
          {costs.isError ? <ErrorAlert error={costs.error} title="The costs could not be read" /> : null}
          {costs.data?.totals?.spentUsd !== undefined ? (
            <Text size="sm" mb="sm">
              <Text span fw={700}>
                {formatUsd(costs.data.totals.spentUsd)}
              </Text>{' '}
              spent on {formatInt(costs.data.totals.liveRuns)} live agent{' '}
              {costs.data.totals.liveRuns === 1 ? 'run' : 'runs'}
              {costs.data.totals.replayedRuns
                ? `; ${formatInt(costs.data.totals.replayedRuns)} replayed ${costs.data.totals.replayedRuns === 1 ? 'run' : 'runs'} cost nothing, since a replay reuses a recorded run`
                : ''}
              {costs.data.totals.mockRuns
                ? `; ${formatInt(costs.data.totals.mockRuns)} ${costs.data.totals.mockRuns === 1 ? 'run' : 'runs'} against the API mimic cost nothing, since no model answered them`
                : ''}
              {costs.data.totals.reviewRuns
                ? `; the production reviews' agent answered ${formatInt(costs.data.totals.reviewRuns)} ${costs.data.totals.reviewRuns === 1 ? 'time' : 'times'}, listed apart below`
                : ''}
              .
            </Text>
          ) : null}
          {costs.data ? (
            <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
              <Stack gap={4}>
                <Text size="sm" fw={600}>
                  By model
                </Text>
                {costs.data.byModel.length === 0 ? (
                  <Text size="sm" c="dimmed">
                    No agent runs recorded.
                  </Text>
                ) : (
                  <Table>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th>Model</Table.Th>
                        <Table.Th>Runs</Table.Th>
                        <Table.Th>Tokens in / out</Table.Th>
                        <Table.Th>Cost</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {costs.data.byModel.map((m) => (
                        <Table.Tr key={`${m.model}|${m.mode ?? ''}`}>
                          <Table.Td>
                            {m.model}
                            {m.mode ? (
                              <Text span size="xs" c="dimmed">
                                {' '}
                                · {m.mode === 'replay' ? 'replayed' : 'live'}
                              </Text>
                            ) : null}
                          </Table.Td>
                          <Table.Td>{m.runs}</Table.Td>
                          <Table.Td>
                            {formatInt(m.promptTokens)} / {formatInt(m.completionTokens)}
                          </Table.Td>
                          <Table.Td>{formatUsd(m.costUsd)}</Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                )}
              </Stack>
              <Stack gap={4}>
                <Text size="sm" fw={600}>
                  By case
                </Text>
                {costs.data.byCase.length === 0 ? (
                  <Text size="sm" c="dimmed">
                    No cases with agent runs.
                  </Text>
                ) : (
                  <Table>
                    <Table.Thead>
                      <Table.Tr>
                        <Table.Th>Case</Table.Th>
                        <Table.Th>Runs</Table.Th>
                        <Table.Th>Cost</Table.Th>
                      </Table.Tr>
                    </Table.Thead>
                    <Table.Tbody>
                      {costs.data.byCase.map((c) => (
                        <Table.Tr key={c.caseId}>
                          <Table.Td>{c.caseId}</Table.Td>
                          <Table.Td>
                            {c.runs}
                            {c.replayedRuns ? ` (${c.replayedRuns} replayed)` : ''}
                          </Table.Td>
                          <Table.Td>{formatUsd(c.costUsd)}</Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                )}
              </Stack>
            </SimpleGrid>
          ) : null}
          {costs.data?.byReview?.length ? (
            <Stack gap={4} mt="md">
              <Text size="sm" fw={600}>
                By production review
              </Text>
              <Table.ScrollContainer minWidth={560}>
                <Table>
                  <Table.Thead>
                    <Table.Tr>
                      <Table.Th>Review</Table.Th>
                      <Table.Th>Production</Table.Th>
                      <Table.Th>Model</Table.Th>
                      <Table.Th>Cost</Table.Th>
                    </Table.Tr>
                  </Table.Thead>
                  <Table.Tbody>
                    {costs.data.byReview.map((r) => (
                      <Table.Tr key={r.reviewId}>
                        <Table.Td>
                          <Anchor
                            component={Link}
                            to={`/reviews/${encodeURIComponent(r.reviewId)}`}
                            size="sm"
                          >
                            {r.reviewId}
                          </Anchor>
                        </Table.Td>
                        <Table.Td>{r.production}</Table.Td>
                        <Table.Td>
                          {r.model || (
                            <Text span size="sm" c="dimmed">
                              none
                            </Text>
                          )}
                          {r.mode ? (
                            <Text span size="xs" c="dimmed">
                              {' '}
                              · {r.mode === 'replay' ? 'replayed' : r.mode}
                            </Text>
                          ) : null}
                        </Table.Td>
                        <Table.Td>{formatUsd(r.costUsd)}</Table.Td>
                      </Table.Tr>
                    ))}
                  </Table.Tbody>
                </Table>
              </Table.ScrollContainer>
            </Stack>
          ) : null}
        </Card>
      </Stack>
    </>
  );
}
