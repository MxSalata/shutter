import { Anchor, Card, Group, Pagination, Select, Table, Text } from '@mantine/core';
import { useState } from 'react';
import { Link } from 'react-router';
import { useCases, type CaseFilters } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DispositionBadge, STATE_HINTS, StateBadge } from '@/components/StateBadge';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';

const PAGE = 25;

export default function CasesPage() {
  const [state, setState] = useState<string | null>(null);
  const [scenario, setScenario] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const filters: CaseFilters = {
    state: state ?? undefined,
    scenario: scenario ?? undefined,
    limit: PAGE,
    offset: (page - 1) * PAGE,
  };
  const cases = useCases(filters);
  const total = cases.data?.total ?? 0;

  return (
    <>
      <PageHeader title="Cases" subtitle="Every failed delivery Interlock opened a case for, newest first." />
      <Card padding="md">
        <Group gap="sm" mb="sm" wrap="wrap">
          <Select
            label="State"
            placeholder="Any state"
            clearable
            value={state}
            onChange={(v) => {
              setState(v);
              setPage(1);
            }}
            data={Object.keys(STATE_HINTS).map((s) => ({ value: s, label: humanize(s) }))}
            w={200}
          />
          <Select
            label="Scenario"
            placeholder="Any scenario"
            clearable
            value={scenario}
            onChange={(v) => {
              setScenario(v);
              setPage(1);
            }}
            data={Array.from({ length: 10 }, (_, i) => `S${i + 1}`)}
            w={160}
          />
        </Group>
        {cases.isPending ? <PageSkeleton label="Loading the cases…" /> : null}
        {cases.isError ? (
          <ErrorAlert
            error={cases.error}
            title="The cases could not be read"
            onRetry={() => void cases.refetch()}
          />
        ) : null}
        {cases.data && cases.data.items.length === 0 ? (
          <Text c="dimmed" size="sm" py="md">
            No cases{state || scenario ? ' match these filters' : ' yet: play a scenario to open one'}.
          </Text>
        ) : null}
        {cases.data && cases.data.items.length > 0 ? (
          <Table.ScrollContainer minWidth={760}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Case</Table.Th>
                  <Table.Th>State</Table.Th>
                  <Table.Th>Disposition</Table.Th>
                  <Table.Th>What failed</Table.Th>
                  <Table.Th>Scenario</Table.Th>
                  <Table.Th>Opened</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {cases.data.items.map((c) => (
                  <Table.Tr key={c.caseId}>
                    <Table.Td>
                      <Anchor
                        component={Link}
                        to={`/cases/${encodeURIComponent(c.caseId)}`}
                        fw={600}
                        size="sm"
                      >
                        {c.caseId}
                      </Anchor>
                    </Table.Td>
                    <Table.Td>
                      <StateBadge state={c.state} />
                    </Table.Td>
                    <Table.Td>
                      <DispositionBadge disposition={c.disposition} />
                    </Table.Td>
                    <Table.Td maw={420}>
                      <Text size="sm" lineClamp={2}>
                        {c.headline ||
                          `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''} for ${c.encounterId}`}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{c.scenario || 'none'}</Text>
                      <Text size="xs" c="dimmed">
                        {humanize(c.mode)}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Timestamp iso={c.openedAt} age />
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        ) : null}
        {total > PAGE ? (
          <Group justify="flex-end" mt="sm">
            <Pagination total={Math.ceil(total / PAGE)} value={page} onChange={setPage} size="sm" />
          </Group>
        ) : null}
      </Card>
    </>
  );
}
