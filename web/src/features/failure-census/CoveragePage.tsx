import {
  Alert,
  Anchor,
  Button,
  Group,
  NativeSelect,
  NumberInput,
  SimpleGrid,
  Stack,
  Table,
  Text,
} from '@mantine/core';
import { IconChecklist } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { API_BASE, newIdempotencyKey, seg } from '@/api/client';
import { useMe } from '@/api/hooks';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Section } from '@/components/Section';
import { Timestamp } from '@/components/Timestamp';
import {
  type CensusOverview,
  type CensusReport,
  isoSeconds,
  REASON_WORDS,
  useCensusOverview,
  useCensusReport,
  useStartCensus,
} from './coverage';

/** A total: unknown when the source could not be read, never a 0 that was not counted. */
const shown = (n: number | null | undefined) => (n === null || n === undefined ? 'unknown' : String(n));

function Count({ label, value }: { label: string; value: string }) {
  return (
    <Stack gap={0}>
      <Text fw={600} size="lg">
        {value}
      </Text>
      <Text size="sm" c="dimmed">
        {label}
      </Text>
    </Stack>
  );
}

/** What the run is worth, first: a report that is not complete must not read as covered. */
function Completeness({ report }: { report: CensusReport }) {
  if (report.completeness === 'complete') {
    return <Text size="sm">Census complete: every delivery in the period was read.</Text>;
  }
  const unknown = report.completeness === 'unknown';
  return (
    <Alert
      color={unknown ? 'red' : 'yellow'}
      variant="light"
      title={unknown ? 'Source reads unavailable: this is not zero failures' : 'Census incomplete'}
    >
      <Stack gap={4}>
        {report.reasons.map((code) => (
          <Text key={code} size="sm">
            {REASON_WORDS[code] ?? code}
          </Text>
        ))}
        {report.sourceError ? (
          <Text size="sm" c="dimmed">
            {report.sourceError}
          </Text>
        ) : null}
      </Stack>
    </Alert>
  );
}

function Report({ runId }: { runId: string }) {
  const report = useCensusReport(runId);
  if (report.isPending) return <PageSkeleton label="Loading the report…" />;
  if (report.isError) return <ErrorAlert error={report.error} title="The report could not be read" />;
  const r = report.data;
  const t = r.totals;
  const items = r.items ?? [];
  return (
    <Section
      id="report"
      title={`${r.runId}: ${r.receiver}`}
      note={`In ${r.namespace}, from ${r.window.from} to ${r.window.to}.`}
      aside={
        <Anchor href={`${API_BASE}/failure-census/${seg(r.runId)}.csv`} size="sm">
          Download CSV
        </Anchor>
      }
    >
      <Stack gap="md">
        <Completeness report={r} />
        <SimpleGrid cols={{ base: 2, sm: 3, md: 6 }}>
          <Count label="Eligible source failures" value={shown(t.eligible)} />
          <Count label="Exactly linked" value={shown(t.exact)} />
          <Count label="No linked case" value={shown(t.none)} />
          <Count label="Ambiguous" value={shown(t.ambiguous)} />
          <Count label="Excluded" value={shown(t.excluded)} />
          <Count label="Cannot be told" value={shown(t.unassessable)} />
        </SimpleGrid>
        <Text size="sm" c="dimmed">
          {shown(t.deliveries)} deliveries read. {shown(t.completed)} completed, outside the failure count: a
          completed acknowledgement says nothing about the application behind it.
        </Text>
        {items.length > 0 ? (
          <Table.ScrollContainer minWidth={720}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Header</Table.Th>
                  <Table.Th>Status</Table.Th>
                  <Table.Th>Family</Table.Th>
                  <Table.Th>Link</Table.Th>
                  <Table.Th>Case</Table.Th>
                  <Table.Th>Why</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {items.map((i) => (
                  <Table.Tr key={`${i.deliveryHeaderId}|${i.originHeaderId}|${i.caseIds}`}>
                    <Table.Td>{i.deliveryHeaderId || `origin ${i.originHeaderId}`}</Table.Td>
                    <Table.Td>{i.sourceStatus}</Table.Td>
                    <Table.Td>{i.family}</Table.Td>
                    <Table.Td>{i.linkQuality}</Table.Td>
                    <Table.Td>
                      {i.caseIds
                        .split(',')
                        .filter(Boolean)
                        .map((id) => (
                          <Anchor key={id} component={Link} to={`/cases/${seg(id)}`} size="sm" mr="xs">
                            {id}
                          </Anchor>
                        ))}
                    </Table.Td>
                    <Table.Td>
                      <CodeChip>{i.explanation}</CodeChip>
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        ) : null}
      </Stack>
    </Section>
  );
}

function RunForm({ overview, onRun }: { overview: CensusOverview; onRun: (runId: string) => void }) {
  const start = useStartCensus();
  const [receiver, setReceiver] = useState(overview.scopes[0]?.receiver ?? '');
  const [hours, setHours] = useState<number | string>(Math.min(24, overview.maxWindowHours));
  const span = Number(hours);
  const spanOk = Number.isInteger(span) && span >= 1 && span <= overview.maxWindowHours;
  const submit = () => {
    const to = new Date();
    start.mutate(
      {
        receiver,
        from: isoSeconds(new Date(to.getTime() - span * 3600 * 1000)),
        to: isoSeconds(to),
        idempotencyKey: newIdempotencyKey(),
      },
      { onSuccess: (r) => onRun(r.runId) },
    );
  };
  if (overview.scopes.length === 0) {
    return <Text size="sm">No receiver is registered yet: onboard a namespace first.</Text>;
  }
  return (
    <Stack gap="sm">
      <Group gap="sm" align="flex-end" wrap="wrap">
        <NativeSelect
          label="Receiver"
          value={receiver}
          onChange={(e) => setReceiver(e.currentTarget.value)}
          data={overview.scopes.map((s) => ({ value: s.receiver, label: `${s.receiver} (${s.namespace})` }))}
        />
        <NumberInput
          label="Hours back from now"
          value={hours}
          onChange={setHours}
          min={1}
          max={overview.maxWindowHours}
          w={160}
        />
        <Button onClick={submit} disabled={!spanOk || receiver === ''} loading={start.isPending}>
          Run the census
        </Button>
      </Group>
      {start.isError ? <ErrorAlert error={start.error} title="The census did not run" /> : null}
    </Stack>
  );
}

export default function CoveragePage() {
  const me = useMe();
  const overview = useCensusOverview();
  const [runId, setRunId] = useState<string | null>(null);
  const data = overview.data;
  return (
    <>
      <PageHeader
        title="Source failure coverage"
        icon={IconChecklist}
        hue="violet"
        lead="Which of a receiver's delivery failures have a Shutter case. It only reads, and never opens a case or resends."
      />
      <Stack gap="md">
        {overview.isPending ? <PageSkeleton label="Loading…" /> : null}
        {overview.isError ? <ErrorAlert error={overview.error} title="The census could not be read" /> : null}
        {data ? (
          <Text size="sm" maw="68ch">
            {data.statement}
          </Text>
        ) : null}
        {data && !data.enabled ? (
          <Alert color="gray" variant="light" title="The census is off">
            <Text size="sm">
              A site turns it on in the{' '}
              <Anchor component={Link} to="/site-profile">
                site profile
              </Anchor>
              , with <CodeChip>failure_census.enabled</CodeChip> true.
            </Text>
          </Alert>
        ) : null}
        {data?.enabled && me.data?.operator ? (
          <Section id="run" title="Run the census">
            <RunForm overview={data} onRun={setRunId} />
          </Section>
        ) : null}
        {runId ? <Report runId={runId} /> : null}
        {data && data.items.length > 0 ? (
          <Section id="runs" title="Latest runs" note="Newest first.">
            <Stack gap={4}>
              {data.items.map((r) => (
                <Group key={r.runId} gap="xs" wrap="wrap">
                  <Anchor component="button" type="button" size="sm" onClick={() => setRunId(r.runId)}>
                    {r.runId}
                  </Anchor>
                  <Text size="sm">{r.receiver}</Text>
                  <CodeChip>{r.completeness}</CodeChip>
                  <Timestamp iso={r.startedAt} size="sm" c="dimmed" />
                </Group>
              ))}
            </Stack>
          </Section>
        ) : null}
      </Stack>
    </>
  );
}
