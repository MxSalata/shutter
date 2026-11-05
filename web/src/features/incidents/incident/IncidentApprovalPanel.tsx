import { Button, Group, List, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconX } from '@tabler/icons-react';
import { resolveCan } from '@/api/can';
import type { IncidentDetail, Me } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { NotYet, Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { APPROVALS } from '@/lib/status';
import { approvalSentence, describePolicy, tidy } from '../describe';
import type { Decision } from './DecideModal';
import { toBecomeApprover } from '@/env/copy';

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
  const why = !resolveCan(me).approve
    ? `Deciding needs the approver role: ${toBecomeApprover()}`
    : !inc.planDigest
      ? 'There is no plan to decide on yet'
      : '';
  return (
    <Section
      id="incident-approval"
      title="Approval"
      note={covered.length ? approvalSentence(covered, decision) : undefined}
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
      {covered.length === 0 && !decision ? (
        <NotYet>No chain of this incident waits for the incident&apos;s approval.</NotYet>
      ) : null}
      {covered.length ? (
        <Stack gap="sm">
          <KeyValueList
            rows={[
              ['Decided', decision?.at ? <Timestamp key="t" iso={decision.at} zone={false} /> : ''],
              ['Comment', decision?.comment ?? ''],
            ]}
          />
          {waiting ? (
            <Stack gap={4}>
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
                <Tooltip
                  label={why || 'Reject the release: nothing is sent for these chains'}
                  disabled={!why}
                >
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
              {why ? (
                <Text size="xs" c="dimmed">
                  {why}
                </Text>
              ) : null}
            </Stack>
          ) : null}
        </Stack>
      ) : null}
      <TechDetail label="What an approval binds" kind="explain">
        <Stack gap={6}>
          {inc.policy ? <Text size="sm">{describePolicy(inc.policy)}.</Text> : null}
          <List size="sm" spacing={4}>
            <List.Item>
              It releases the chains the site&apos;s policy leaves to a person: resend these, in this order.
              Each one is rehearsed, gated and verified just before it goes.
            </List.Item>
            <List.Item>
              It binds the plan&apos;s digest, and each operation after the first goes at exactly the version
              the one before it verified.
            </List.Item>
            <List.Item>
              Each operation goes only under the catalogue entry and outcome listed for it. A chain stops at
              the first surprise, and one whose fresh evidence reads differently comes back to a person.
            </List.Item>
          </List>
        </Stack>
      </TechDetail>
      {inc.tasks.length ? (
        <TechDetail label="Approval tasks" kind="data">
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
                      <Text size="sm">{tidy(t.subject)}</Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Answer">
                      <Text size="sm">{t.complete ? t.action || 'done' : 'open'}</Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="By">
                      <Text size="sm">{t.userName || t.assignedTo || 'unassigned'}</Text>
                    </StackTable.Td>
                    <StackTable.Td data-label="Completed">
                      <Timestamp iso={t.timeCompleted} zone={false} />
                    </StackTable.Td>
                  </StackTable.Tr>
                ))}
              </StackTable.Tbody>
            </StackTable>
          </Table.ScrollContainer>
        </TechDetail>
      ) : null}
    </Section>
  );
}
