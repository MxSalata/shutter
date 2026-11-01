import { Anchor, Card, Group, NativeSelect, Table, Text, Title } from '@mantine/core';
import { useState } from 'react';
import { Link } from 'react-router';
import { useIncidents, useSettings } from '@/api/hooks';
import type { HeldMessages } from '@/api/types';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { IncidentStateBadge } from './badges';
import { describeOutcomes, describePolicy, describeProgress, INCIDENT_STATES } from './describe';

/**
 * The interfaces whose messages are held because their HL7 schema is not loaded here (the site prevents failures,
 * CONTRACTS 6.7): each is a case of its own, not an incident, so they are listed by schema category above the incidents.
 */
function HeldInterfaces({ held }: { held: HeldMessages }) {
  return (
    <Card padding="md" mb="md" data-testid="held-interfaces">
      <Title order={2} fz="lg" mb={4}>
        Held: a schema not loaded here
      </Title>
      <Text size="sm" c="dimmed" mb="sm">
        The site prevents failures, so Shutter holds every message whose HL7 schema category this namespace
        lacks and sends nothing. Import the schema and set the inbound item&apos;s category to it (INSTALL.md
        section 7); the held cases are then checked again and sent under the site&apos;s policy.
      </Text>
      <Table.ScrollContainer minWidth={420}>
        <Table>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Schema category</Table.Th>
              <Table.Th>Held messages</Table.Th>
              <Table.Th>Oldest</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {held.categories.map((c) => (
              <Table.Tr key={c.category}>
                <Table.Td>
                  <Text size="sm" className="mono-wrap">
                    {c.category}
                  </Text>
                </Table.Td>
                <Table.Td>{c.count}</Table.Td>
                <Table.Td>{c.oldest ? <Timestamp iso={c.oldest} /> : null}</Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Card>
  );
}

export default function IncidentsPage() {
  const [state, setState] = useState<string | null>(null);
  const incidents = useIncidents({ state: state ?? undefined, limit: 100 });
  const held = useSettings().data?.heldMessages;

  return (
    <>
      <PageHeader
        title="Incidents"
        subtitle="Many failures to one receiver, grouped: chains per encounter, released in order and verified one operation at a time."
      />
      {held && held.count > 0 ? <HeldInterfaces held={held} /> : null}
      <Card padding="md" data-tour="incidents-list">
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
