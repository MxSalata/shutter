import { Button, Group, List, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconX } from '@tabler/icons-react';
import type { IncidentDetail, Me } from '@/api/types';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { StackTable } from '@/components/StackTable';
import { APPROVALS } from '@/lib/status';
import { NotYet, Section } from '../../cases/case/Section';
import { describePolicy } from '../describe';
import type { Decision } from './DecideModal';

export function IncidentApprovalPanel({
  inc,
  me,
  onDecide,
}: {
  inc: IncidentDetail;
  me: Me;
  onDecide: (d: Decision) => void;
}) {
  const covered = inc.chains.filter((c) => c.decides === 'policy' && c.policy === 'approval');
  const waiting = covered.some((c) => c.state === 'awaiting_approval');
  const decision = inc.approvals.find((a) => a.scope === 'incident');
  const why = !me.approver
    ? 'Deciding needs the approver role: sign in as approver'
    : !inc.planDigest
      ? 'There is no plan to decide on yet'
      : '';
  return (
    <Section
      id="incident-approval"
      title="Approval"
      note="One approval releases the chains the site's policy leaves to a person: resend these, in this order; each one is rehearsed, gated and verified just before it goes; a chain stops at the first surprise, and the rest comes back to a person. It binds the plan's digest, and each operation after the first goes at exactly the version the one before it verified. Each operation goes only under the catalogue entry and outcome listed for it; one whose fresh evidence reads differently stops its chain and comes back to a person."
      aside={
        decision ? (
          decision.decision === 'approved' ? (
            <StatusBadge {...APPROVALS.approved} label={`Approved by ${decision.by}`} />
          ) : (
            <StatusBadge {...APPROVALS.rejected} label={`Rejected by ${decision.by}`} />
          )
        ) : waiting ? (
          <StatusBadge {...APPROVALS.awaiting} />
        ) : null
      }
    >
      <Text size="sm">{describePolicy(inc.policy)}.</Text>
      {covered.length === 0 && !decision ? (
        <NotYet>No chain of this incident waits for the incident's approval.</NotYet>
      ) : null}
      {covered.length ? (
        <Stack gap="sm">
          <List size="sm" spacing={2}>
            {covered.map((c) => (
              <List.Item key={c.seq}>
                Chain {c.seq} ({c.encounterId}): {c.items.length} operation{c.items.length === 1 ? '' : 's'},{' '}
                {c.items.map((i) => i.caseId).join(' then ')}
              </List.Item>
            ))}
          </List>
          <KeyValueList
            rows={[
              ['Plan digest', <Digest key="p" value={inc.planDigest} label="incident plan digest" />],
              ['Decided', decision?.at ? <Timestamp key="t" iso={decision.at} /> : ''],
              ['Comment', decision?.comment ?? ''],
            ]}
          />
          {waiting ? (
            <Group gap="sm">
              <Tooltip label={why || "Approve the release of the incident's policy chains"} disabled={!why}>
                <span>
                  <Button
                    leftSection={<IconCheck size={16} />}
                    disabled={!!why}
                    onClick={() => onDecide('approve')}
                  >
                    Approve release
                  </Button>
                </span>
              </Tooltip>
              <Tooltip label={why || 'Reject the release: nothing is sent for these chains'} disabled={!why}>
                <span>
                  <Button
                    color="red"
                    variant="light"
                    leftSection={<IconX size={16} />}
                    disabled={!!why}
                    onClick={() => onDecide('reject')}
                  >
                    Reject release
                  </Button>
                </span>
              </Tooltip>
            </Group>
          ) : null}
        </Stack>
      ) : null}
      {inc.tasks.length ? (
        <Table.ScrollContainer minWidth={520} className="stack-scroll">
          <StackTable verticalSpacing={4} className="stack-table">
            <StackTable.Thead>
              <StackTable.Tr>
                <StackTable.Th>Approval task</StackTable.Th>
                <StackTable.Th>Answer</StackTable.Th>
                <StackTable.Th>By</StackTable.Th>
                <StackTable.Th>Completed</StackTable.Th>
              </StackTable.Tr>
            </StackTable.Thead>
            <StackTable.Tbody>
              {inc.tasks.map((t) => (
                <StackTable.Tr key={t.taskId}>
                  <StackTable.Td>
                    <Text size="sm">{t.subject}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Answer">
                    <Text size="sm">{t.complete ? t.action || 'done' : 'open'}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="By">
                    <Text size="sm">{t.userName || t.assignedTo || 'unassigned'}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Completed">
                    <Timestamp iso={t.timeCompleted} />
                  </StackTable.Td>
                </StackTable.Tr>
              ))}
            </StackTable.Tbody>
          </StackTable>
        </Table.ScrollContainer>
      ) : null}
    </Section>
  );
}
