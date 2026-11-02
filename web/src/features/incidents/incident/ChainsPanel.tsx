import { Anchor, Button, Card, Group, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconHandStop, IconX } from '@tabler/icons-react';
import { Link } from 'react-router';
import { resolveCan } from '@/api/can';
import type { Chain, ChainItem, IncidentDetail, Me } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { NotYet, Section } from '@/components/Section';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { useTechnical } from '@/stores/appearance';
import { ChainStateBadge, KindBadge, OperationBadge } from '../badges';
import { CHAIN_STATES, chainLine, describeChain, versions } from '../describe';
import type { Decision } from './DecideModal';

/** A tooltip that opens for the keyboard and a touch as well as the pointer. */
const REACHABLE = { hover: true, focus: true, touch: true };

/** What the version step means, said once for every operation's "v1 → v2". */
const VERSION_HINT =
  'The receiver version the operation goes at, and the version its verification read: each operation after the first goes at exactly the version the one before it verified';

/** The catalogue's match when the chain formed, and the released case's own when it differs. */
const movedAtRelease = (item: ChainItem) =>
  !!item.releaseEntry && (item.releaseEntry !== item.entry || item.releaseOutcome !== item.outcome);

/** "At release: E1 · none", when the released case found something other than the entry the chain formed under. */
function AtRelease({ item }: { item: ChainItem }) {
  if (!movedAtRelease(item)) return null;
  return (
    <Text size="xs" c="dimmed">
      At release: {item.releaseEntry}
      {item.releaseOutcome ? ` · ${humanize(item.releaseOutcome).toLowerCase()}` : ''}
      {item.state === 'blocked' ? ' (not covered by the approval: the chain stopped here)' : ''}
    </Text>
  );
}

/** The catalogue entry and outcome as codes, the operation's key and the case's full sentence: the expert's layer. */
function OperationDetail({ item }: { item: ChainItem }) {
  return (
    <Stack gap={4}>
      <Group gap={6} wrap="wrap">
        {item.entry ? <CodeChip>{item.entry}</CodeChip> : null}
        {item.outcome ? <CodeChip>{item.outcome}</CodeChip> : null}
        {item.operationKey ? <CodeChip>{item.operationKey}</CodeChip> : null}
      </Group>
      <AtRelease item={item} />
      {item.caseHeadline ? (
        <TechDetail label={`More about ${item.caseId}`} kind="explain">
          <Text size="sm">{item.caseHeadline}</Text>
        </TechDetail>
      ) : null}
    </Stack>
  );
}

/** One operation of a chain: its case, event, time, version step and what came of it. */
function Operation({ chain, item }: { chain: Chain; item: ChainItem }) {
  const technical = useTechnical();
  return (
    <li className="chain-op">
      <span className="chain-op-num" aria-hidden>
        {item.position}
      </span>
      <Stack gap={4} className="chain-op-body">
        <Group gap="xs" wrap="wrap" align="baseline">
          <Anchor component={Link} to={`/cases/${encodeURIComponent(item.caseId)}`} size="sm" fw={600}>
            {item.caseId}
          </Anchor>
          <Text size="sm" span>
            {humanize(item.event)}
          </Text>
          <Timestamp iso={item.eventTime} size="xs" c="dimmed" />
        </Group>
        <Group gap="xs" wrap="wrap">
          <Tooltip label={VERSION_HINT} multiline maw={320} events={REACHABLE}>
            <Text size="sm" span tabIndex={0}>
              {versions(item)}
            </Text>
          </Tooltip>
          <OperationBadge item={item} />
          {chain.stoppedAt === item.position ? (
            <StatusBadge tone="blocking" label="Stopped the chain" icon={IconHandStop} variant="outline" />
          ) : null}
        </Group>
        {technical ? <OperationDetail item={item} /> : null}
      </Stack>
    </li>
  );
}

function ChainCard({
  chain,
  me,
  onDecide,
}: {
  chain: Chain;
  me: Me | null | undefined;
  onDecide: (d: Decision, chain: Chain) => void;
}) {
  const technical = useTechnical();
  const ownApproval = chain.state === 'awaiting_approval' && chain.policy === 'per_chain';
  const why = !resolveCan(me).approve ? 'Deciding needs the approver role: sign in as approver' : '';
  const entries = (chain.entries ?? '').split(',').filter(Boolean);
  return (
    <Card padding="sm" withBorder component="article" aria-label={`Chain ${chain.seq}, ${chain.encounterId}`}>
      <Stack gap="xs">
        <Group justify="space-between" wrap="wrap" gap="xs" align="flex-start">
          <Stack gap={2} style={{ minWidth: 0, flex: '1 1 240px' }}>
            <Group gap="xs" wrap="wrap">
              <Text fw={600}>
                Chain {chain.seq}: {chain.encounterId}
              </Text>
              <KindBadge kind={chain.kind} />
            </Group>
            <Tooltip label={describeChain(chain)} events={REACHABLE}>
              <Text size="sm" tabIndex={0} w="fit-content">
                {chainLine(chain)}
              </Text>
            </Tooltip>
            {technical ? (
              <Group gap={6} wrap="wrap">
                {chain.patientId ? (
                  <Text size="xs" c="dimmed" span>
                    patient <CodeChip>{chain.patientId}</CodeChip>
                  </Text>
                ) : null}
                <CodeChip>{chain.decides}</CodeChip>
                {chain.policy ? <CodeChip>{chain.policy}</CodeChip> : null}
                {entries.map((e, i) => (
                  <CodeChip key={i}>{e}</CodeChip>
                ))}
              </Group>
            ) : null}
          </Stack>
          <ChainStateBadge state={chain.state} />
        </Group>
        {chain.approval ? (
          <Text size="xs" c="dimmed">
            {humanize(chain.approval.decision)} by {chain.approval.by}
            {chain.approval.comment ? `: "${chain.approval.comment}"` : ''}
          </Text>
        ) : null}
        {ownApproval ? (
          <Group gap="sm">
            <Tooltip label={why || 'Approve the release of this chain alone'} disabled={!why}>
              <span>
                <Button
                  size="xs"
                  leftSection={<IconCheck size={14} />}
                  disabled={!!why}
                  onClick={() => onDecide('approve', chain)}
                >
                  Approve this chain
                </Button>
              </span>
            </Tooltip>
            <Tooltip label={why || 'Reject this chain: its cases go to a person'} disabled={!why}>
              <span>
                <Button
                  size="xs"
                  color="red"
                  variant="light"
                  leftSection={<IconX size={14} />}
                  disabled={!!why}
                  onClick={() => onDecide('reject', chain)}
                >
                  Reject this chain
                </Button>
              </span>
            </Tooltip>
          </Group>
        ) : null}
        {/* Two or three operations run side by side with an arrow between them on a laptop; the rest stack */}
        <ol
          role="list"
          className="chain-ops"
          data-flow={chain.items.length >= 2 && chain.items.length <= 3 ? 'row' : 'stack'}
          aria-label={`Chain ${chain.seq} operations, oldest first`}
        >
          {chain.items.map((item) => (
            <Operation key={item.position} chain={chain} item={item} />
          ))}
        </ol>
      </Stack>
    </Card>
  );
}

/** Today's tables, for the reader who wants every column: one per chain, behind one disclosure for the panel. */
function OperationTables({ chains }: { chains: Chain[] }) {
  return (
    <TechDetail label="Show the operations as tables" kind="explain">
      <Stack gap="md">
        {chains.map((chain) => (
          <Stack gap={4} key={chain.seq}>
            <Text fw={600} size="sm">
              Chain {chain.seq}: {chain.encounterId}
            </Text>
            <Table.ScrollContainer minWidth={640}>
              <Table verticalSpacing={4} aria-label={`Operations of chain ${chain.seq}`}>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>#</Table.Th>
                    <Table.Th>Operation</Table.Th>
                    <Table.Th>Event time</Table.Th>
                    <Table.Th>Catalogue</Table.Th>
                    <Table.Th>
                      <Tooltip label={VERSION_HINT} multiline maw={320} events={REACHABLE}>
                        <span tabIndex={0}>Receiver version</span>
                      </Tooltip>
                    </Table.Th>
                    <Table.Th>State</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {chain.items.map((item) => (
                    <Table.Tr key={item.position}>
                      <Table.Td>{item.position}</Table.Td>
                      <Table.Td>
                        <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                          {item.caseId}
                        </Text>
                        <Text size="xs" c="dimmed">
                          {humanize(item.event)}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Timestamp iso={item.eventTime} style={{ whiteSpace: 'nowrap' }} />
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm">
                          {item.entry || 'no entry'}
                          {item.outcome ? ` · ${humanize(item.outcome).toLowerCase()}` : ''}
                        </Text>
                      </Table.Td>
                      <Table.Td>
                        <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                          {versions(item)}
                        </Text>
                      </Table.Td>
                      <Table.Td maw={320}>
                        <OperationBadge item={item} />
                        {item.caseHeadline ? (
                          <Text size="xs" c="dimmed" mt={4}>
                            {item.caseHeadline}
                          </Text>
                        ) : null}
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          </Stack>
        ))}
      </Stack>
    </TechDetail>
  );
}

export function ChainsPanel({
  inc,
  me,
  onDecide,
}: {
  inc: IncidentDetail;
  me: Me | null | undefined;
  onDecide: (d: Decision, chain: Chain) => void;
}) {
  const byState = Object.entries(inc.progress?.byState ?? {});
  return (
    <Section
      id="chains"
      tour="incident-chains"
      title="Chains"
      note="One chain per patient encounter, its messages sent oldest first."
      aside={byState.map(([state, n]) => {
        const status = CHAIN_STATES[state] ?? {
          tone: 'neutral' as const,
          hint: state,
          label: humanize(state),
        };
        return <StatusBadge {...status} key={state} label={`${n} ${status.label.toLowerCase()}`} />;
      })}
    >
      <TechDetail label="How chains are released" kind="explain">
        <Text size="sm" maw="68ch">
          One chain per encounter, its failed operations oldest event first. A chain the catalogue settles
          goes by the site&apos;s policy; any other chain&apos;s cases each go to the board. Chains are
          released one at a time, and within a chain one operation at a time, each through its own case&apos;s
          dispatch.
        </Text>
      </TechDetail>
      {inc.chains.length === 0 ? (
        <NotYet>
          No chains yet: they form when the intake has closed and every case it took has its evidence.
        </NotYet>
      ) : null}
      {inc.chains.map((chain) => (
        <ChainCard key={chain.seq} chain={chain} me={me} onDecide={onDecide} />
      ))}
      {inc.chains.length ? <OperationTables chains={inc.chains} /> : null}
    </Section>
  );
}
