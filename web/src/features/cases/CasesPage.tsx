import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  NativeSelect,
  Pagination,
  SimpleGrid,
  Stack,
  Table,
  Text,
  Tooltip,
} from '@mantine/core';
import {
  IconCircleCheck,
  IconCircleMinus,
  IconListDetails,
  IconTargetOff,
  IconTool,
  type Icon as TablerIcon,
} from '@tabler/icons-react';
import { useId, useMemo, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useListParams } from '@/lib/listParams';
import { useCases, useFailedForAPerson, useScenarios, type CaseFilters } from '@/api/hooks';
import type { CaseSummary, Scenario } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { EmptyState } from '@/components/EmptyState';
import { ErrorAlert } from '@/components/ErrorAlert';
import { IdentityBadge } from '@/components/IdentityBadge';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { StackTable } from '@/components/StackTable';
import { CASE_STATE_NAMES, DispositionBadge } from '@/components/StateBadge';
import { StatTile } from '@/components/StatTile';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { ToneLegend } from '@/components/ToneLegend';
import { humanize, plural } from '@/lib/format';
import { clampHeadline, cutEscalation } from '@/lib/headline';
import type { Hue } from '@/lib/hues';
import {
  caseOutcome,
  caseState,
  verification,
  writes,
  type CaseOutcomeKey,
  type ExpectedScenario,
} from '@/lib/status';
import type { Tone } from '@/lib/tone';
import { useTechnical } from '@/stores/appearance';
import { forwardedFrom } from './case/derive';
import { CaseTechLine } from './case/TechFacts';
import './cases-list.css';

const PAGE = 25;

/** How many of the newest cases the Closed tiles count over (the API filters by state only). */
const NEWEST = 100;

/** The states a case is in before anyone has made its plan. */
const BEFORE_PLAN = new Set(['detected', 'collecting', 'investigating', 'grouped']);

/**
 * What reached the receiver and what the verifier found, when the server sends them; a closed case with no write says
 * so. In Technical the receiver's item names its class, when the server sends it.
 */
function AtReceiver({ c }: { c: CaseSummary }) {
  const technical = useTechnical();
  // A case is one failed delivery to one receiver: with two receivers fed, the list says which
  const name = c.receiver ? (
    <Text size="xs" c="dimmed">
      {c.receiver}
      {technical && c.receiverClass ? (
        <>
          {' '}
          <CodeChip fz="xs" data-testid="case-receiver-class">
            {c.receiverClass}
          </CodeChip>
        </>
      ) : null}
    </Text>
  ) : null;
  if (c.writes === undefined) return name;
  return (
    <div className="at-receiver">
      {name}
      <StatusBadge {...writes(c.writes)} />
      {c.verification ? <StatusBadge {...verification(c.verification)} /> : null}
    </div>
  );
}

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
  if (by.startsWith('policy:')) return { who: 'Site policy (no agents)', entry: by.slice('policy:'.length) };
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

/** The identity hue of the ways a plan is made; any other answer (not yet, withheld, unknown) is plain text. */
const WHO_HUE: Record<string, Hue> = {
  Board: 'violet',
  'Site policy (no agents)': 'teal',
  'Single investigator': 'gray',
  'Rules only': 'gray',
};

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
  const technical = useTechnical();
  const { who, entry } = investigatedBy(c);
  const hue = WHO_HUE[who];
  return (
    <Stack gap={2} align="flex-start" className="case-who">
      {hue ? <IdentityBadge hue={hue}>{who}</IdentityBadge> : <Text size="sm">{who}</Text>}
      {entry ? (
        <Text size="xs" c="dimmed">
          entry {technical ? <CodeChip>{entry}</CodeChip> : entry}
        </Text>
      ) : null}
    </Stack>
  );
}

/** What the state means for the proposal beside it, where the two could read as a contradiction or a person is due. */
export function proposalNote(c: Pick<CaseSummary, 'state' | 'disposition'>): string {
  if (!c.disposition) return '';
  if (c.state === 'blocked') return 'Stopped: nothing more is sent';
  if (c.state === 'awaiting_approval') return 'Waiting for a person to release it';
  if (c.state === 'escalated') return 'A person decides';
  return '';
}

const wordCount = (s: string) => s.split(/\s+/).filter(Boolean).length;

/**
 * What happened, in sentences: the headline's first sentence in full (a sentence of under six words, such as "Valid
 * message." or "Escalated to a person.", takes the next one with it), and the rest for the "More about" disclosure.
 * Never cut with an ellipsis: an escalation the server cut stops at its catalogue entry's title, and the rest holds the
 * cut text. A case with no headline reads what the summary's own fields say.
 */
export function whatHappened(c: Pick<CaseSummary, 'headline' | 'event' | 'ward' | 'encounterId'>): {
  first: string;
  rest: string;
} {
  const text = clampHeadline(c.headline).trim();
  if (!text)
    return {
      first: `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''} for ${c.encounterId}`,
      rest: '',
    };
  const entry = cutEscalation(text);
  if (entry) return entry;
  const sentences = text.split(/(?<=[.!?])\s+(?=[A-Z0-9(])/);
  let first = sentences[0];
  let used = 1;
  while (wordCount(first) < 6 && used < sentences.length) first += ` ${sentences[used++]}`;
  return { first, rest: sentences.slice(used).join(' ') };
}

/**
 * The cell of what happened: the first sentence, in Technical the message, where it came in, its trace and its plan
 * (CaseTechLine), and the rest behind its own button.
 */
function WhatHappened({ c }: { c: CaseSummary }) {
  const technical = useTechnical();
  const { first, rest } = whatHappened(c);
  return (
    <Stack gap={4} align="flex-start">
      <Text size="sm">{first}</Text>
      {technical ? <CaseTechLine c={c} /> : null}
      {rest ? (
        <TechDetail label={`More about ${c.caseId}`} kind="explain">
          <Text size="sm">{rest}</Text>
        </TechDetail>
      ) : null}
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
    </Stack>
  );
}

/**
 * The list's cases; on a phone each case is a compact card: its id and outcome, what happened, then one line of facts.
 * `scenarios` are the cases' scenarios, for the outcome that compares a case with what its scenario expects.
 */
export function CasesTable({
  items,
  scenarios = [],
}: {
  items: CaseSummary[];
  scenarios?: ExpectedScenario[];
}) {
  const byId = new Map(scenarios.map((s) => [s.id, s]));
  return (
    <Table.ScrollContainer minWidth={760} className="stack-scroll">
      <StackTable className="stack-table stack-cards cases-table" horizontalSpacing={7}>
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Case</StackTable.Th>
            <StackTable.Th>Outcome</StackTable.Th>
            <StackTable.Th>Proposed action</StackTable.Th>
            <StackTable.Th>At the receiver</StackTable.Th>
            <StackTable.Th>What happened</StackTable.Th>
            <StackTable.Th>Scenario</StackTable.Th>
            <StackTable.Th>Investigated by</StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {items.map((c) => {
            const scenario = byId.get(c.scenario);
            const outcome = caseOutcome(c, scenario);
            return (
              <StackTable.Tr key={c.caseId} data-tone={outcome.tone} className="case-row">
                <StackTable.Td>
                  <Group gap={6} wrap="nowrap">
                    <Anchor
                      component={Link}
                      to={`/cases/${encodeURIComponent(c.caseId)}`}
                      fw={600}
                      size="sm"
                      className="case-open"
                      style={{ whiteSpace: 'nowrap' }}
                    >
                      {c.caseId}
                    </Anchor>
                    <ForwardedBadge c={c} />
                  </Group>
                  <Timestamp iso={c.openedAt} age size="xs" />
                </StackTable.Td>
                <StackTable.Td data-label="Outcome">
                  <OutcomeBadge c={c} scenario={scenario} />
                </StackTable.Td>
                <StackTable.Td data-label="Proposed action" data-label-hidden className="case-last">
                  <DispositionBadge disposition={c.disposition} />
                  {proposalNote(c) ? (
                    <Text size="xs" c="dimmed" mt={2}>
                      {proposalNote(c)}
                    </Text>
                  ) : null}
                </StackTable.Td>
                <StackTable.Td data-label="At the receiver" data-label-hidden className="case-meta">
                  <AtReceiver c={c} />
                </StackTable.Td>
                <StackTable.Td
                  data-label="What happened"
                  data-label-hidden
                  maw={420}
                  className="stack-line case-line"
                >
                  <WhatHappened c={c} />
                </StackTable.Td>
                <StackTable.Td data-label="Scenario" data-label-hidden className="case-meta">
                  <Text size="sm">{c.scenario || 'none'}</Text>
                  <Text size="xs" c="dimmed" className="case-mode">
                    {humanize(c.mode)}
                  </Text>
                </StackTable.Td>
                <StackTable.Td data-label="Investigated by" data-label-hidden className="case-meta">
                  <InvestigatedBy c={c} />
                </StackTable.Td>
              </StackTable.Tr>
            );
          })}
        </StackTable.Tbody>
      </StackTable>
    </Table.ScrollContainer>
  );
}

/** The states that need a person, first: each a tile that filters the list, with its count from the API. */
const ATTENTION = ['awaiting_approval', 'escalated', 'blocked'] as const;

/** A tile's accessible name: its figure, its words and what pressing does, so "15 Escalated Show these". */
const tileName = (n: number | string | undefined, label: string, caption: string) =>
  `${n === undefined ? '' : `${n} `}${label} ${caption}`;

/** What a tile says (one word, to keep the page's words few) and what its accessible name adds. */
const SHOW = { seen: 'Show', name: 'Show these' };
const SHOWING = { seen: 'Showing; press to clear', name: 'Showing these; press to clear' };

/** A failed case needs a person too; its tile shows only when there is one, or a tile of nought would say nothing. */
function FailedTile({
  n,
  chosen,
  onChoose,
}: {
  n: number | undefined;
  chosen: boolean;
  onChoose: () => void;
}) {
  const o = caseOutcome({ state: 'failed', disposition: '' });
  const caption = chosen ? SHOWING : SHOW;
  return (
    <StatTile
      label={o.short}
      figure={n === undefined ? '…' : n}
      caption={caption.seen}
      tone={o.tone}
      icon={o.icon as TablerIcon | undefined}
      onClick={onChoose}
      pressed={chosen}
      aria-label={tileName(n, o.short, caption.name)}
    />
  );
}

export function AttentionTile({
  state,
  chosen,
  onChoose,
}: {
  state: (typeof ATTENTION)[number];
  chosen: boolean;
  onChoose: () => void;
}) {
  const count = useCases({ state, limit: 1 });
  const o = caseOutcome({ state, disposition: '' });
  const n = count.data?.total;
  const caption = chosen ? SHOWING : SHOW;
  return (
    <StatTile
      label={o.short}
      figure={n === undefined ? '…' : n}
      caption={caption.seen}
      tone={o.tone}
      icon={o.icon as TablerIcon | undefined}
      onClick={onChoose}
      pressed={chosen}
      aria-label={tileName(n, o.short, caption.name)}
    />
  );
}

/**
 * The closed outcomes the tiles count: a case that ended otherwise than its scenario expects (shown only when there is
 * one, as a tile of nought would say nothing), a delivery the verifier confirmed, a case with nothing to send (verified
 * or not, since both say the receiver needed nothing), and a case a person handled or gave up.
 */
export const CLOSED_GROUPS: {
  id: 'unexpected' | 'delivered' | 'nothing' | 'by-hand';
  label: string;
  tone: Tone;
  icon: TablerIcon;
  keys: CaseOutcomeKey[];
}[] = [
  {
    id: 'unexpected',
    label: 'Not as expected',
    tone: 'blocking',
    icon: IconTargetOff,
    keys: ['not-as-expected'],
  },
  {
    id: 'delivered',
    label: 'Delivered, verified',
    tone: 'positive',
    icon: IconCircleCheck,
    keys: ['delivered'],
  },
  {
    id: 'nothing',
    label: 'Nothing to send',
    tone: 'neutral',
    icon: IconCircleMinus,
    keys: ['nothing-to-send-verified', 'nothing-to-send'],
  },
  {
    id: 'by-hand',
    label: 'By hand',
    tone: 'neutral',
    icon: IconTool,
    keys: ['handled-by-hand', 'abandoned'],
  },
];

export type ClosedGroupId = (typeof CLOSED_GROUPS)[number]['id'];

/** The cases of a closed outcome group, among those given, each judged against its own scenario's expectation. */
export function casesOfGroup(
  items: CaseSummary[],
  group: ClosedGroupId,
  scenarioOf: (c: CaseSummary) => ExpectedScenario | undefined,
): CaseSummary[] {
  const keys = CLOSED_GROUPS.find((g) => g.id === group)?.keys ?? [];
  return items.filter((c) => keys.includes(caseOutcome(c, scenarioOf(c)).key));
}

/** How many of the given cases are in each closed outcome group. */
export function closedCounts(
  items: CaseSummary[],
  scenarioOf: (c: CaseSummary) => ExpectedScenario | undefined,
): Record<ClosedGroupId, number> {
  return {
    unexpected: casesOfGroup(items, 'unexpected', scenarioOf).length,
    delivered: casesOfGroup(items, 'delivered', scenarioOf).length,
    nothing: casesOfGroup(items, 'nothing', scenarioOf).length,
    'by-hand': casesOfGroup(items, 'by-hand', scenarioOf).length,
  };
}

/** A closed outcome's tile: how many of the newest cases ended that way; pressed, it filters the list to them. */
export function ClosedTile({
  group,
  count,
  chosen,
  onChoose,
}: {
  group: (typeof CLOSED_GROUPS)[number];
  count: number | undefined;
  chosen: boolean;
  onChoose: () => void;
}) {
  const caption = chosen ? SHOWING : SHOW;
  return (
    <StatTile
      label={group.label}
      figure={count === undefined ? '…' : count}
      caption={caption.seen}
      tone={group.tone}
      icon={group.icon}
      onClick={onChoose}
      pressed={chosen}
      aria-label={tileName(count, group.label, caption.name)}
    />
  );
}

/** A labelled group of tiles. */
function TileGroup({ title, four, children }: { title: string; four?: boolean; children: ReactNode }) {
  const id = useId();
  return (
    <section aria-labelledby={id}>
      <Text id={id} className="overline" mb={6}>
        {title}
      </Text>
      <SimpleGrid cols={four ? { base: 2, md: 4 } : 3} spacing="xs" className="cases-tiles">
        {children}
      </SimpleGrid>
    </section>
  );
}

/** The request the list's page reads, as an engineer would type it. */
function requestOf(filters: CaseFilters): string {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== '') params.set(k, String(v));
  return `GET /api/shutter/cases?${params.toString()}`;
}

export default function CasesPage() {
  // The filter and the page live in the address, so Back from a case returns to this list and not the first page of all
  const [params, change] = useListParams();
  const asked = params.get('state');
  const state = asked && (CASE_STATE_NAMES as readonly string[]).includes(asked) ? asked : null;
  // A closed outcome chosen from the Closed tiles: the list then shows those cases among the newest 100
  const outcome = CLOSED_GROUPS.find((g) => g.id === params.get('outcome'))?.id ?? null;
  // A link from the Scenarios page names its scenario (S22: one case per receiver)
  const scenario = params.get('scenario');
  const page = Math.max(1, Math.floor(Number(params.get('page'))) || 1);
  // One write for all of them
  const setList = (patch: {
    state?: string | null;
    outcome?: string | null;
    scenario?: string | null;
    page?: number;
  }) => {
    change((next) => {
      for (const [k, v] of Object.entries(patch)) {
        if (v && !(k === 'page' && v === 1)) next.set(k, String(v));
        else next.delete(k);
      }
    });
  };
  const filters: CaseFilters = {
    state: state ?? undefined,
    scenario: scenario ?? undefined,
    limit: PAGE,
    offset: (page - 1) * PAGE,
  };
  const paged = useCases(filters, outcome === null);
  const newest = useCases({ limit: NEWEST });
  const failed = useFailedForAPerson();
  // A chosen tile stays, or the filter on show could not be turned off where it was turned on
  const failedShown = (failed ?? 0) > 0 || state === 'failed';
  const scenarios = useScenarios();
  const scenarioList: Scenario[] = useMemo(() => scenarios.data?.scenarios ?? [], [scenarios.data]);
  const byId = useMemo(() => new Map(scenarioList.map((s) => [s.id, s])), [scenarioList]);
  const scenarioOf = (c: CaseSummary) => byId.get(c.scenario);

  const newestItems = newest.data?.items;
  const counts = useMemo(
    () =>
      newestItems && !scenarios.isPending ? closedCounts(newestItems, (c) => byId.get(c.scenario)) : null,
    [newestItems, scenarios.isPending, byId],
  );
  // A chosen tile stays, or the filter on show could not be turned off where it was turned on
  const closedShown = CLOSED_GROUPS.filter(
    (g) => g.id !== 'unexpected' || outcome === g.id || (counts?.unexpected ?? 0) > 0,
  );
  // More cases than the read holds: the Closed tiles count the newest ones only, and say so
  const overBase = (newest.data?.total ?? 0) > NEWEST;

  // The list on show: the server's page, or (a closed outcome chosen) that outcome's cases among the newest 100
  const chosenOutcome = outcome ? newestItems && casesOfGroup(newestItems, outcome, scenarioOf) : undefined;
  const matching = chosenOutcome?.filter((c) => !scenario || c.scenario === scenario);
  const read = outcome ? newest : paged;
  const items = outcome ? matching?.slice((page - 1) * PAGE, page * PAGE) : paged.data?.items;
  const total = outcome ? (matching?.length ?? 0) : (paged.data?.total ?? 0);
  // A page past the end, from an old address, offers the way back as a filter does
  const filtered = state !== null || outcome !== null || scenario !== null || page > 1;

  const choose = (next: { state?: string | null; outcome?: ClosedGroupId | null }) =>
    setList({ state: next.state ?? null, outcome: next.outcome ?? null, page: 1 });
  const scenarioIds = scenarioList.map((s) => s.id);
  if (scenario && !scenarioIds.includes(scenario)) scenarioIds.push(scenario);

  return (
    <>
      <PageHeader
        title="Cases"
        icon={IconListDetails}
        hue="indigo"
        lead="Every failed delivery, newest first. The tiles show which need a person."
      />
      <Stack gap="md">
        <div className="cases-tile-groups" data-closed={closedShown.length} data-need={failedShown ? 4 : 3}>
          <TileGroup title="Needs a person" four={failedShown}>
            {ATTENTION.map((a) => (
              <AttentionTile
                key={a}
                state={a}
                chosen={state === a && outcome === null}
                onChoose={() => choose({ state: state === a ? null : a })}
              />
            ))}
            {failedShown ? (
              <FailedTile
                n={failed}
                chosen={state === 'failed' && outcome === null}
                onChoose={() => choose({ state: state === 'failed' ? null : 'failed' })}
              />
            ) : null}
          </TileGroup>
          <TileGroup title={overBase ? 'Closed, in the newest 100' : 'Closed'} four={closedShown.length > 3}>
            {closedShown.map((g) => (
              <ClosedTile
                key={g.id}
                group={g}
                count={counts?.[g.id]}
                chosen={outcome === g.id}
                onChoose={() => choose({ outcome: outcome === g.id ? null : g.id })}
              />
            ))}
          </TileGroup>
        </div>
        <Stack gap={6} className="cases-legend">
          <ToneLegend />
          <TechDetail label="How to read this list" kind="explain">
            <Text size="sm" maw="68ch">
              Outcome is where the case stands, and what came of it. Proposed action is what its plan
              proposed, which the gate can still stop: Blocked beside Resend is a resend that was proposed and
              blocked. At the receiver is what was written and what the verifier found there. Investigated by
              is who made the plan.
            </Text>
          </TechDetail>
        </Stack>
        <Card padding="md" data-tour="cases-list">
          <Group gap="sm" mb="sm" wrap="wrap" align="flex-end">
            <NativeSelect
              label="State"
              value={state ?? ''}
              onChange={(e) => choose({ state: e.currentTarget.value || null })}
              data={[
                { value: '', label: 'Any state' },
                ...CASE_STATE_NAMES.map((s) => ({ value: s, label: caseState(s).label })),
              ]}
              w={200}
            />
            <NativeSelect
              label="Scenario"
              value={scenario ?? ''}
              onChange={(e) => setList({ scenario: e.currentTarget.value || null, page: 1 })}
              data={[{ value: '', label: 'Any scenario' }, ...scenarioIds]}
              w={170}
            />
            {read.data ? (
              <Text size="sm" c="dimmed" pb={6} ml="auto" aria-live="polite">
                {plural(total, 'case')}
              </Text>
            ) : null}
          </Group>
          {outcome && overBase ? (
            <Text size="sm" mb="sm">
              Showing the newest {NEWEST} cases with this outcome
            </Text>
          ) : null}
          {read.isPending || (scenarios.isPending && !read.isError) ? (
            <PageSkeleton label="Loading the cases…" />
          ) : null}
          {read.isError ? (
            <ErrorAlert
              error={read.error}
              title="The cases could not be read"
              onRetry={() => void read.refetch()}
            />
          ) : null}
          {read.data && !scenarios.isPending && items && items.length === 0 ? (
            <EmptyState
              icon={IconListDetails}
              hue="indigo"
              action={
                filtered ? (
                  <Button
                    size="xs"
                    variant="default"
                    onClick={() => setList({ state: null, outcome: null, scenario: null, page: 1 })}
                  >
                    Show every case
                  </Button>
                ) : (
                  <Anchor component={Link} to="/scenarios" size="sm">
                    Play a scenario
                  </Anchor>
                )
              }
            >
              {filtered ? 'No cases match these filters.' : 'No cases yet. Play a scenario to open one.'}
            </EmptyState>
          ) : null}
          {read.data && !scenarios.isPending && items && items.length > 0 ? (
            <CasesTable items={items} scenarios={scenarioList} />
          ) : null}
          {total > PAGE ? (
            <Group justify="flex-end" mt="sm">
              <Pagination
                total={Math.ceil(total / PAGE)}
                value={page}
                onChange={(n) => setList({ page: n })}
                size="sm"
                getControlProps={(control) => ({ 'aria-label': `${control} page` })}
                getItemProps={(n) => ({ 'aria-label': `Page ${n}` })}
              />
            </Group>
          ) : null}
          {read.data ? (
            <ApiSource
              endpoint={requestOf(outcome ? { limit: NEWEST } : filters)}
              data={outcome ? newest.data : paged.data}
            />
          ) : null}
        </Card>
      </Stack>
    </>
  );
}
