import { Badge, Card, Group, SimpleGrid, Stack, Table, Text, Title } from '@mantine/core';
import { useCosts, useSettings } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { formatInt, formatUsd, humanize } from '@/lib/format';
import type { AgentItem } from '@/api/types';

function Flag({ on, yes, no }: { on: boolean; yes: string; no: string }) {
  return (
    <Badge color={on ? 'teal' : 'gray'} variant="light" style={{ textTransform: 'none' }}>
      {on ? yes : no}
    </Badge>
  );
}

type ItemColumn = {
  key: 'mode' | 'model' | 'providerConfig' | 'maxIterations' | 'tokenBudget';
  label: string;
};
const ITEM_COLUMNS: ItemColumn[] = [
  { key: 'mode', label: 'Mode' },
  { key: 'model', label: 'Model' },
  { key: 'providerConfig', label: 'Provider' },
  { key: 'maxIterations', label: 'Iterations' },
  { key: 'tokenBudget', label: 'Token budget' },
];

/** The agent items, with only the settings some item has: a replaying item has no model or limits. */
function AgentItemsTable({ items }: { items: AgentItem[] }) {
  const columns = ITEM_COLUMNS.filter((c) => items.some((a) => a[c.key] !== undefined && a[c.key] !== ''));
  const show = (c: ItemColumn, a: AgentItem) => {
    const v = a[c.key];
    if (v === undefined || v === '') return '—';
    if (c.key === 'mode') return humanize(String(v));
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
              <Group gap="sm" wrap="wrap">
                <Flag on={s.aiHubPresent} yes="AI Hub present" no="No AI Hub: recorded runs only" />
                <Flag on={s.liveRunnerPresent} yes="Live runner installed" no="No live runner" />
                <Flag on={s.demo} yes="Demo instance" no="Not a demo instance" />
                <Text size="sm">Mode: {humanize(s.mode)}</Text>
                {s.scenario ? <Text size="sm">Scenario: {s.scenario}</Text> : null}
                {s.resetAt ? (
                  <Group gap={4}>
                    <Text size="sm">Last reset</Text>
                    <Timestamp iso={s.resetAt} />
                  </Group>
                ) : null}
              </Group>
            </Card>
            <Card padding="md">
              <Title order={2} fz="lg" mb="sm">
                Agent items
              </Title>
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
                        <Table.Tr key={m.model}>
                          <Table.Td>{m.model}</Table.Td>
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
                          <Table.Td>{c.runs}</Table.Td>
                          <Table.Td>{formatUsd(c.costUsd)}</Table.Td>
                        </Table.Tr>
                      ))}
                    </Table.Tbody>
                  </Table>
                )}
              </Stack>
            </SimpleGrid>
          ) : null}
        </Card>
      </Stack>
    </>
  );
}
