import { Anchor, Card, Group, NativeSelect, Table, Text } from '@mantine/core';
import { useState } from 'react';
import { Link } from 'react-router';
import { useIncidents } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { IncidentStateBadge } from './badges';
import { describeOutcomes, describePolicy, describeProgress, INCIDENT_STATES } from './describe';

export default function IncidentsPage() {
  const [state, setState] = useState<string | null>(null);
  const incidents = useIncidents({ state: state ?? undefined, limit: 100 });

  return (
    <>
      <PageHeader
        title="Incidents"
        subtitle="Many failures to one receiver, grouped: chains per encounter, released in order and verified one operation at a time."
      />
      <Card padding="md">
        <Group gap="sm" mb="sm" wrap="wrap">
          <NativeSelect
            label="State"
            value={state ?? ''}
            onChange={(e) => setState(e.currentTarget.value || null)}
            data={[
              { value: '', label: 'Any state' },
              ...Object.keys(INCIDENT_STATES).map((s) => ({ value: s, label: humanize(s) })),
            ]}
            w={200}
          />
        </Group>
        {incidents.isPending ? <PageSkeleton label="Loading the incidents…" /> : null}
        {incidents.isError ? (
          <ErrorAlert
            error={incidents.error}
            title="The incidents could not be read"
            onRetry={() => void incidents.refetch()}
          />
        ) : null}
        {incidents.data && incidents.data.items.length === 0 ? (
          <Text c="dimmed" size="sm" py="md">
            {state
              ? 'No incidents in this state.'
              : 'No incidents yet: an incident opens when several deliveries to one receiver fail within a few minutes (scenarios S11 and S12).'}
          </Text>
        ) : null}
        {incidents.data && incidents.data.items.length > 0 ? (
          <Table.ScrollContainer minWidth={760}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Incident</Table.Th>
                  <Table.Th>State</Table.Th>
                  <Table.Th>Receiver</Table.Th>
                  <Table.Th>What it holds</Table.Th>
                  <Table.Th>Chains</Table.Th>
                  <Table.Th>Opened</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {incidents.data.items.map((i) => (
                  <Table.Tr key={i.incidentId}>
                    <Table.Td>
                      <Anchor
                        component={Link}
                        to={`/incidents/${encodeURIComponent(i.incidentId)}`}
                        fw={600}
                        size="sm"
                      >
                        {i.incidentId}
                      </Anchor>
                    </Table.Td>
                    <Table.Td>
                      <IncidentStateBadge state={i.state} />
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{i.receiver}</Text>
                      <Text size="xs" c="dimmed">
                        {humanize(i.mode)}
                      </Text>
                    </Table.Td>
                    <Table.Td maw={320}>
                      <Text size="sm">{describeProgress(i)}</Text>
                      {i.policy ? (
                        <Text size="xs" c="dimmed">
                          {describePolicy(i.policy)}
                        </Text>
                      ) : null}
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{describeOutcomes(i)}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Timestamp iso={i.openedAt} age />
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        ) : null}
      </Card>
    </>
  );
}
