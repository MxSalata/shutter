import { Anchor, Badge, Card, Group, Pagination, Select, Table, Text, Tooltip } from '@mantine/core';
import { useState } from 'react';
import { Link } from 'react-router';
import { useCases, useScenarios, type CaseFilters } from '@/api/hooks';
import type { CaseSummary } from '@/api/types';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { CASE_STATE_NAMES, DispositionBadge, StateBadge } from '@/components/StateBadge';
import { Timestamp } from '@/components/Timestamp';
import { StackTable } from '@/components/StackTable';
import { caseState } from '@/lib/status';
import { humanize } from '@/lib/format';
import { clampHeadline } from '@/lib/headline';
import { forwardedFrom } from './case/derive';

const PAGE = 25;

/** The states a case is in before anyone has made its plan. */
const BEFORE_PLAN = new Set(['detected', 'collecting', 'investigating', 'grouped']);

/**
 * Who investigated the case and made its plan: the board, the single investigator, rules alone, the site's policy
 * (the catalogue entry it matched), or nobody for a withheld operation, which a person decides. The plan's origin says
 * it exactly, and the server sends it only when the case has a plan. With none, a case on its way to a plan says so, a
 * withheld one says a person decides, and any other reads the mode, which in site-policy mode cannot tell the policy
 * from the board.
 */
export function investigatedBy(c: CaseSummary): { who: string; entry?: string } {
  const by = c.planCreatedBy ?? '';
  if (by.startsWith('run:')) return { who: c.mode === 'single' ? 'Single investigator' : 'Board' };
  if (by.startsWith('policy:')) return { who: 'Site policy', entry: by.slice('policy:'.length) };
  if (by === 'rules') return { who: 'Rules only' };
  if (by === 'withheld') return { who: 'Withheld: a person decides' };
  if (by) return { who: '-' };
  if (BEFORE_PLAN.has(c.state)) return { who: 'Not yet' };
  if (c.failureKind === 'withheld') return { who: 'Withheld: a person decides' };
  const byMode: Record<string, string> = {
    board: 'Board',
    single: 'Single investigator',
    rules: 'Rules only',
    policy: 'Site policy or board',
  };
  return { who: byMode[c.mode] ?? '-' };
}

/** A case another production forwarded (CONTRACTS 11); the tooltip says where its message came from. */
export function ForwardedBadge({ c }: { c: CaseSummary }) {
  const from = forwardedFrom({
    namespace: c.sourceNamespace,
    production: c.sourceProduction,
    route: c.sourceRoute,
    headerId: c.originHeaderId,
  });
  if (!from) return null;
  return (
    <Tooltip label={`Forwarded from ${from}`} multiline maw={320}>
      <Badge size="xs" variant="outline" color="gray" tabIndex={0} style={{ textTransform: 'none' }}>
        Forwarded
      </Badge>
    </Tooltip>
  );
}

/** The list's cell: who investigated, and the catalogue entry when the site's policy settled the case. */
export function InvestigatedBy({ c }: { c: CaseSummary }) {
  const { who, entry } = investigatedBy(c);
  return (
    <>
      <Text size="sm">{who}</Text>
      {entry ? (
        <Text size="xs" c="dimmed">
          entry {entry}
        </Text>
      ) : null}
    </>
  );
}

/** The list's cases; on a phone each case is a card: its id, then each column's value under the column's name. */
export function CasesTable({ items }: { items: CaseSummary[] }) {
  return (
    <Table.ScrollContainer minWidth={760} className="stack-scroll">
      <StackTable className="stack-table">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Case</StackTable.Th>
            <StackTable.Th>State</StackTable.Th>
            <StackTable.Th>Proposed action</StackTable.Th>
            <StackTable.Th>What failed</StackTable.Th>
            <StackTable.Th>Scenario</StackTable.Th>
            <StackTable.Th>Investigated by</StackTable.Th>
            <StackTable.Th>Opened</StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {items.map((c) => (
            <StackTable.Tr key={c.caseId}>
              <StackTable.Td>
                <Group gap={6} wrap="nowrap">
                  <Anchor
                    component={Link}
                    to={`/cases/${encodeURIComponent(c.caseId)}`}
                    fw={600}
                    size="sm"
                    style={{ whiteSpace: 'nowrap' }}
                  >
                    {c.caseId}
                  </Anchor>
                  <ForwardedBadge c={c} />
                </Group>
              </StackTable.Td>
              <StackTable.Td data-label="State">
                <StateBadge state={c.state} />
              </StackTable.Td>
              <StackTable.Td data-label="Proposed action">
                <DispositionBadge disposition={c.disposition} />
              </StackTable.Td>
              <StackTable.Td data-label="What failed" maw={420}>
                <Text size="sm" lineClamp={2}>
                  {clampHeadline(c.headline) ||
                    `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''} for ${c.encounterId}`}
                </Text>
                {c.incidentId ? (
                  <Text size="xs" c="dimmed">
                    In incident{' '}
                    <Anchor
                      component={Link}
                      to={`/incidents/${encodeURIComponent(c.incidentId)}`}
                      size="xs"
                      underline="always"
                    >
                      {c.incidentId}
                    </Anchor>
                  </Text>
                ) : null}
              </StackTable.Td>
              <StackTable.Td data-label="Scenario">
                <Text size="sm">{c.scenario || 'none'}</Text>
                <Text size="xs" c="dimmed">
                  {humanize(c.mode)}
                </Text>
              </StackTable.Td>
              <StackTable.Td data-label="Investigated by">
                <InvestigatedBy c={c} />
              </StackTable.Td>
              <StackTable.Td data-label="Opened">
                <Timestamp iso={c.openedAt} age />
              </StackTable.Td>
            </StackTable.Tr>
          ))}
        </StackTable.Tbody>
      </StackTable>
    </Table.ScrollContainer>
  );
}

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
  const scenarioIds = useScenarios().data?.scenarios.map((s) => s.id) ?? [];

  return (
    <>
      <PageHeader title="Cases" subtitle="Every failed delivery Shutter opened a case for, newest first." />
      <Card padding="md" data-tour="cases-list">
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
            data={CASE_STATE_NAMES.map((s) => ({ value: s, label: caseState(s).label }))}
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
            data={scenarioIds}
            w={160}
          />
        </Group>
        {/* What the columns mean, once: a proposal beside a Blocked state is what was proposed and stopped */}
        <Text size="sm" c="dimmed" mb="sm" maw="100ch">
          State is where the case is now. Proposed action is what its plan proposed, which the gate can still
          stop: Blocked beside Resend is a resend that was proposed and blocked. Investigated by is who made
          the plan: the rules alone, one agent, the board (three specialists and a coordinator) or the
          site&apos;s written policy.
        </Text>
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
        {cases.data && cases.data.items.length > 0 ? <CasesTable items={cases.data.items} /> : null}
        {total > PAGE ? (
          <Group justify="flex-end" mt="sm">
            <Pagination
              total={Math.ceil(total / PAGE)}
              value={page}
              onChange={setPage}
              size="sm"
              getControlProps={(control) => ({ 'aria-label': `${control} page` })}
              getItemProps={(n) => ({ 'aria-label': `Page ${n}` })}
            />
          </Group>
        ) : null}
      </Card>
    </>
  );
}
