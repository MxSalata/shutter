import { Badge, Button, Group, List, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconX } from '@tabler/icons-react';
import type { IncidentDetail, Me } from '@/api/types';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
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
      note="One approval releases the chains the site's policy leaves to a person: resend these, in this order; each one is rehearsed, gated and verified just before it goes; a chain stops at the first surprise, and the rest comes back to a person. It binds the plan's digest, and each operation after the first goes at exactly the version the one before it verified."
      aside={
        decision ? (
          <Badge color={decision.decision === 'approved' ? 'teal' : 'red'} style={{ textTransform: 'none' }}>
            {decision.decision === 'approved' ? `Approved by ${decision.by}` : `Rejected by ${decision.by}`}
          </Badge>
        ) : waiting ? (
          <Badge color="yellow" style={{ textTransform: 'none' }}>
            Waiting for an approver
          </Badge>
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
                    color="teal"
                    leftSection={<IconCheck size={16} />}
                    disabled={!!why}
                    onClick={() => onDecide('approve')}
                  >
                    Approve…
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
                    Reject…
                  </Button>
                </span>
              </Tooltip>
            </Group>
          ) : null}
        </Stack>
      ) : null}
      {inc.tasks.length ? (
        <Table.ScrollContainer minWidth={520}>
          <Table verticalSpacing={4}>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Workflow task</Table.Th>
                <Table.Th>Answer</Table.Th>
                <Table.Th>By</Table.Th>
                <Table.Th>Completed</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {inc.tasks.map((t) => (
                <Table.Tr key={t.taskId}>
                  <Table.Td>
                    <Text size="sm">{t.subject}</Text>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm">{t.complete ? t.action || 'done' : 'open'}</Text>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm">{t.userName || t.assignedTo || 'unassigned'}</Text>
                  </Table.Td>
                  <Table.Td>
                    <Timestamp iso={t.timeCompleted} />
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      ) : null}
    </Section>
  );
}
