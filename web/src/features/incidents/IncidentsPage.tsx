import { Anchor, Card, Group, NativeSelect, Stack, Table, Text, Title, Tooltip } from '@mantine/core';
import { IconStack2 } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { useIncidents, useSettings, useSiteProfile } from '@/api/hooks';
import type { HeldMessages, IncidentSummary, LiveStorm } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { EmptyState } from '@/components/EmptyState';
import { ErrorAlert } from '@/components/ErrorAlert';
import { IdentityBadge } from '@/components/IdentityBadge';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { StackTable } from '@/components/StackTable';
import { StatTile } from '@/components/StatTile';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { SummaryBand } from '@/components/SummaryBand';
import { Term } from '@/components/Term';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { TRIAL } from '@/env/mode';
import { StormStrip } from '@/features/storm/StormStrip';
import { humanize, plural } from '@/lib/format';
import { MODE_IDENTITY } from '@/lib/hues';
import { incidentOutcome } from '@/lib/status';
import { isStormShown } from '@/lib/storm';
import { useNow } from '@/lib/useNow';
import { HINT_EVENTS } from '@/theme';
import { ChainBar } from './ChainBar';
import { describeHeld, describeKinds, describePolicy, INCIDENT_STATES, statesFromCounts } from './describe';
import './incidents.css';
import { OutageSection } from './outage/OutageSection';

/**
 * The interfaces whose messages are held because their HL7 schema is not loaded here (the site prevents failures,
 * CONTRACTS 6.7): each is a case of its own, not an incident, so they are listed by schema category above the incidents.
 */
function HeldInterfaces({ held }: { held: HeldMessages }) {
  return (
    <Stack gap="sm" mb="md" data-testid="held-interfaces">
      <StatusNotice
        tone="attention"
        title={
          <Title order={2} fz="md">
            Held: a schema not loaded here
          </Title>
        }
      >
        <Text size="sm">
          The site prevents failures, so Shutter holds every message whose HL7 schema category this namespace
          lacks and sends nothing.
        </Text>
        <TechDetail label="How to release them" kind="explain">
          <Text size="sm">
            Import the schema where it is missing and set the inbound item&apos;s category to it (INSTALL.md
            section 7); the held cases are then checked again and sent under the site&apos;s policy.
          </Text>
        </TechDetail>
      </StatusNotice>
      <Card padding="md">
        <Table.ScrollContainer minWidth={420}>
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Schema category</Table.Th>
                <Table.Th>Missing in</Table.Th>
                <Table.Th>Held messages</Table.Th>
                <Table.Th>Oldest</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {held.categories.map((c) => (
                <Table.Tr key={`${c.namespace ?? ''}:${c.category}`}>
                  <Table.Td>
                    <Text size="sm" className="mono-wrap">
                      {c.category}
                    </Text>
                  </Table.Td>
                  <Table.Td>{c.namespace ?? ''}</Table.Td>
                  <Table.Td>{c.count}</Table.Td>
                  <Table.Td>{c.oldest ? <Timestamp iso={c.oldest} /> : null}</Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      </Card>
    </Stack>
  );
}

/**
 * "Break the feed" while a storm plays on the live hospital, or has just finished: the banner's strip, here in its own
 * card above the incidents, where the storm's incident appears (the banner leaves its strip out on this page).
 */
function StormCard({ storm }: { storm: LiveStorm }) {
  return (
    <Card padding="md" data-testid="incidents-storm">
      <StormStrip
        storm={storm}
        place="page"
        heading={
          <Title order={2} fz="md">
            Break the feed
          </Title>
        }
      />
    </Card>
  );
}

/** The three figures that matter on the list: what is open, what is closed, and how the chains came out. */
function Tiles({ items }: { items: IncidentSummary[] }) {
  const open = items.filter((i) => i.state !== 'closed');
  const needPerson = open.filter((i) => incidentOutcome(i).tone === 'attention').length;
  const sum = (pick: (i: IncidentSummary) => number) => items.reduce((n, i) => n + pick(i), 0);
  const chains = sum((i) => i.progress?.chains ?? 0);
  const verified = sum((i) => i.progress?.byState.resolved ?? 0);
  const stopped = sum((i) => (i.progress?.byState.stopped ?? 0) + (i.progress?.byState.rejected ?? 0));
  return (
    <SummaryBand title="Incidents at a glance" cols={{ base: 1, sm: 3 }}>
      <StatTile
        label="Open"
        figure={open.length}
        caption="taking cases or releasing"
        tone={open.length === 0 ? undefined : needPerson ? 'attention' : 'info'}
        status={
          open.length === 0 ? undefined : needPerson ? (
            <StatusBadge
              {...INCIDENT_STATES.awaiting_approval}
              label={`${needPerson} ${needPerson === 1 ? 'needs' : 'need'} a person`}
            />
          ) : (
            <StatusBadge {...INCIDENT_STATES.open} label="In progress" />
          )
        }
      />
      <StatTile label="Closed" figure={items.length - open.length} caption="every chain has an outcome" />
      <StatTile
        label={<Term term="chain">Chains</Term>}
        figure={chains ? `${verified} of ${chains}` : 0}
        caption="verified"
        tone={chains && verified === chains ? 'positive' : stopped ? 'blocking' : undefined}
        status={
          chains && verified === chains ? (
            <StatusBadge tone="positive" label="All verified" />
          ) : stopped ? (
            <StatusBadge tone="blocking" label={`${stopped} stopped`} />
          ) : undefined
        }
      />
    </SummaryBand>
  );
}

/** The incident's run mode, with how its policy chains were authorised in a tooltip (once, not on every row). */
function ModeMark({ mode, policy }: { mode: string; policy: string | undefined }) {
  const id = MODE_IDENTITY[mode];
  const mark = <IdentityBadge hue={id?.hue ?? 'gray'}>{id?.label ?? humanize(mode)}</IdentityBadge>;
  const tip = describePolicy(policy);
  if (!tip) return mark;
  return (
    <Tooltip label={tip} multiline maw={320} events={HINT_EVENTS}>
      <span tabIndex={0}>{mark}</span>
    </Tooltip>
  );
}

/** No incidents, said once: when one opens, from the site profile's threshold and window. */
function NoIncidents() {
  const incident = useSiteProfile().data?.profile.incident;
  const rule =
    incident?.threshold && incident.window_minutes
      ? `${incident.threshold} deliveries to one receiver fail within ${plural(incident.window_minutes, 'minute')}`
      : 'several deliveries to one receiver fail within a few minutes';
  return (
    <EmptyState
      icon={IconStack2}
      hue="pink"
      action={
        <Anchor component={Link} to="/site-profile" size="sm">
          Site profile
        </Anchor>
      }
    >
      No incidents yet. One opens when {rule}.
    </EmptyState>
  );
}

export default function IncidentsPage() {
  const [state, setState] = useState<string | null>(null);
  const incidents = useIncidents({ limit: 100 });
  const settings = useSettings().data;
  const held = settings?.heldMessages;
  // The banner in the frame reads the settings every 3 s while a storm plays, so this page follows it too
  const now = useNow();
  const live = settings?.live?.enabled ? settings.live : undefined;
  const storm = !TRIAL && live?.storm && isStormShown(live.storm, now) ? live.storm : null;
  const all = incidents.data?.items ?? [];
  const shown = state ? all.filter((i) => i.state === state) : all;

  if (incidents.isPending) return <PageSkeleton label="Loading the incidents…" shape="header-tiles-table" />;
  return (
    <>
      <PageHeader
        title="Incidents"
        icon={IconStack2}
        hue="pink"
        lead="Many failures to one receiver, handled together and released in order."
        details="Chains per encounter, released in order and verified one operation at a time."
      />
      <Stack gap="md">
        {storm ? <StormCard storm={storm} /> : null}
        <OutageSection />
        {held && held.count > 0 ? <HeldInterfaces held={held} /> : null}
        {incidents.isError ? (
          <ErrorAlert
            error={incidents.error}
            title="The incidents could not be read"
            onRetry={() => void incidents.refetch()}
          />
        ) : null}
        {incidents.data && all.length === 0 ? (
          <Card padding="md" data-tour="incidents-list">
            <NoIncidents />
          </Card>
        ) : null}
        {incidents.data && all.length > 0 ? (
          <>
            <Tiles items={all} />
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
              {shown.length === 0 ? (
                <Text c="dimmed" size="sm" py="md">
                  No incidents in this state.
                </Text>
              ) : (
                <Table.ScrollContainer minWidth={760} className="stack-scroll">
                  <StackTable className="stack-table stack-cards incident-list">
                    <StackTable.Thead>
                      <StackTable.Tr>
                        <StackTable.Th>Incident</StackTable.Th>
                        <StackTable.Th>Outcome</StackTable.Th>
                        <StackTable.Th>What it holds</StackTable.Th>
                        <StackTable.Th>Receiver</StackTable.Th>
                        <StackTable.Th>Opened</StackTable.Th>
                      </StackTable.Tr>
                    </StackTable.Thead>
                    <StackTable.Tbody>
                      {shown.map((i) => {
                        const outcome = incidentOutcome(i);
                        return (
                          <StackTable.Tr key={i.incidentId} className="tone-row" data-tone={outcome.tone}>
                            <StackTable.Td>
                              <Anchor
                                component={Link}
                                to={`/incidents/${encodeURIComponent(i.incidentId)}`}
                                fw={600}
                                size="sm"
                              >
                                {i.incidentId}
                              </Anchor>
                            </StackTable.Td>
                            <StackTable.Td data-label="Outcome" data-label-hidden>
                              <StatusBadge {...outcome} />
                            </StackTable.Td>
                            <StackTable.Td data-label="What it holds" className="stack-line">
                              <Group gap="xs" wrap="wrap">
                                <Text size="sm">{describeHeld(i)}</Text>
                                <ChainBar states={statesFromCounts(i.progress?.byState)} />
                                <Text size="xs" c="dimmed">
                                  {describeKinds(i)}
                                </Text>
                              </Group>
                            </StackTable.Td>
                            <StackTable.Td data-label="Receiver" className="stack-meta">
                              <Group gap={6} wrap="wrap">
                                <Text size="sm" span>
                                  {i.receiver}
                                </Text>
                                <ModeMark mode={i.mode} policy={i.policy} />
                              </Group>
                            </StackTable.Td>
                            <StackTable.Td data-label="Opened" className="stack-meta">
                              <Timestamp iso={i.openedAt} age />
                            </StackTable.Td>
                          </StackTable.Tr>
                        );
                      })}
                    </StackTable.Tbody>
                  </StackTable>
                </Table.ScrollContainer>
              )}
            </Card>
          </>
        ) : null}
        {incidents.data ? (
          <ApiSource endpoint="GET /api/shutter/incidents?limit=100" data={incidents.data} />
        ) : null}
      </Stack>
    </>
  );
}
