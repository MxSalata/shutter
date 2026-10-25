import { Anchor, Button, Card, Group, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconHandStop, IconX } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { Chain, ChainItem, IncidentDetail, Me } from '@/api/types';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { NotYet, Section } from '../../cases/case/Section';
import { ChainStateBadge, ItemStateBadge, KindBadge } from '../badges';
import { CHAIN_STATES, describeChain, describeProgress } from '../describe';
import type { Decision } from './DecideModal';

/** "v1 → v2": the receiver version the operation went at, and the one its verification read. */
function versions(item: ChainItem): string {
  const at = item.expectedVersion === null ? 'fresh evidence' : `v${item.expectedVersion}`;
  if (item.verifiedVersion !== null) return `${at} → v${item.verifiedVersion}`;
  return item.state === 'pending' || item.state === 'released' ? `${at} → …` : at;
}

/** The catalogue's match when the chain formed, and the released case's own when it differs. */
function Match({ item }: { item: ChainItem }) {
  const moved =
    item.releaseEntry && (item.releaseEntry !== item.entry || item.releaseOutcome !== item.outcome);
  return (
    <Stack gap={0}>
      <Text size="sm">
        {item.entry || 'no entry'}
        {item.outcome ? ` · ${humanize(item.outcome).toLowerCase()}` : ''}
      </Text>
      {moved ? (
        <Text size="xs" c="dimmed">
          At release: {item.releaseEntry}
          {item.releaseOutcome ? ` · ${humanize(item.releaseOutcome).toLowerCase()}` : ''}
          {item.state === 'blocked' ? ' (not covered by the approval: the chain stopped here)' : ''}
        </Text>
      ) : null}
    </Stack>
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
  const ownApproval = chain.state === 'awaiting_approval' && chain.policy === 'per_chain';
  const why = !me?.approver ? 'Deciding needs the approver role: sign in as approver' : '';
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
            <Text size="xs" c="dimmed">
              {describeChain(chain)}
              {chain.patientId ? ` · patient ${chain.patientId}` : ''}
            </Text>
          </Stack>
          <ChainStateBadge state={chain.state} />
        </Group>
        {chain.outcome ? <Text size="sm">{chain.outcome}</Text> : null}
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
                  Approve this chain…
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
                  Reject…
                </Button>
              </span>
            </Tooltip>
          </Group>
        ) : null}
        <Table.ScrollContainer minWidth={640}>
          <Table verticalSpacing={4}>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>#</Table.Th>
                <Table.Th>Operation</Table.Th>
                <Table.Th>Event time</Table.Th>
                <Table.Th>Catalogue</Table.Th>
                <Table.Th>
                  <Tooltip
                    label="The receiver version the operation goes at, and the version its verification read: each operation after the first goes at exactly the version the one before it verified"
                    multiline
                    maw={320}
                  >
                    <span tabIndex={0}>Receiver version</span>
                  </Tooltip>
                </Table.Th>
                <Table.Th>State</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {chain.items.map((item) => (
                <Table.Tr key={item.position}>
                  <Table.Td>
                    <Text size="sm">{item.position}</Text>
                  </Table.Td>
                  <Table.Td>
                    <Anchor
                      component={Link}
                      to={`/cases/${encodeURIComponent(item.caseId)}`}
                      size="sm"
                      style={{ whiteSpace: 'nowrap' }}
                    >
                      {item.caseId}
                    </Anchor>
                    <Text size="xs" c="dimmed">
                      {humanize(item.event)}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Timestamp iso={item.eventTime} style={{ whiteSpace: 'nowrap' }} />
                  </Table.Td>
                  <Table.Td>
                    <Match item={item} />
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm" style={{ whiteSpace: 'nowrap' }}>
                      {versions(item)}
                    </Text>
                  </Table.Td>
                  <Table.Td maw={260}>
                    <Group gap={4}>
                      <ItemStateBadge state={item.state} />
                      {chain.stoppedAt === item.position ? (
                        <StatusBadge
                          tone="blocking"
                          label="Stopped the chain"
                          icon={IconHandStop}
                          variant="outline"
                        />
                      ) : null}
                    </Group>
                    {item.caseHeadline ? (
                      <Text size="xs" c="dimmed" lineClamp={2}>
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
    </Card>
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
      note="One chain per encounter, its failed operations oldest event first. A chain the catalogue settles goes by the site's policy; any other chain's cases each go to the board. Chains are released one at a time, and within a chain one operation at a time, each through its own case's dispatch."
      aside={byState.map(([state, n]) => (
        <StatusBadge
          key={state}
          {...(CHAIN_STATES[state] ?? { tone: 'neutral', hint: state })}
          label={`${n} ${humanize(state).toLowerCase()}`}
        />
      ))}
    >
      <Text size="sm">{describeProgress(inc)}</Text>
      {inc.chains.length === 0 ? (
        <NotYet>
          No chains yet: they form when the intake has closed and every case it took has its evidence.
        </NotYet>
      ) : null}
      {inc.chains.map((chain) => (
        <ChainCard key={chain.seq} chain={chain} me={me} onDecide={onDecide} />
      ))}
    </Section>
  );
}
