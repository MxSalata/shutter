import { Alert, Badge, Button, Group, Modal, Stack, Table, Text, Textarea, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCheck, IconEye, IconX } from '@tabler/icons-react';
import { useState } from 'react';
import { usePreviewBlindResend, useDecideApproval } from '@/api/hooks';
import { newIdempotencyKey } from '@/api/client';
import type { ApprovalsView, CaseDetail, Me, PlanView } from '@/api/types';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { describeError, isApiError } from '@/lib/errors';
import { asObject } from '@/lib/json';
import { humanize } from '@/lib/format';
import { NotYet, Section } from './Section';

function BlindResendPreview({ c, me }: { c: CaseDetail; me: Me }) {
  const preview = usePreviewBlindResend(c.caseId);
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(c.state);
  const why = !me.operator ? 'The preview needs the operator role' : closed ? 'The case is closed' : '';
  const r = preview.data;
  const after = asObject(r?.encounterAfter);
  return (
    <Stack gap="xs">
      <Group gap="sm">
        <Tooltip
          label={
            why ||
            'Ask the ward what the original message would do if it were simply sent again, with no version check. Nothing is written.'
          }
          multiline
          maw={320}
        >
          <span>
            <Button
              variant="light"
              color="orange"
              size="xs"
              leftSection={<IconEye size={14} />}
              disabled={!!why}
              loading={preview.isPending}
              onClick={() => preview.mutate()}
            >
              What would a blind resend do?
            </Button>
          </span>
        </Tooltip>
      </Group>
      {preview.isError ? (
        <Alert color="red" variant="light">
          {describeError(preview.error)}
        </Alert>
      ) : null}
      {r ? (
        <Alert
          color={r.wouldApply ? 'orange' : 'gray'}
          variant="light"
          title={r.wouldApply ? 'A blind resend would apply' : 'A blind resend would be refused'}
        >
          <Stack gap={4}>
            {after ? (
              <Text size="sm">
                Afterwards the ward would hold {humanize(String(after.state ?? ''))}
                {after.ward ? ` in ${String(after.ward)}` : ''}, version {String(after.version ?? '')}.
              </Text>
            ) : null}
            {r.reason ? <Text size="sm">Reason: {humanize(r.reason)}</Text> : null}
            {r.note ? <Text size="sm">{r.note}</Text> : null}
            <Text size="xs" c="dimmed">
              The ward's dry run, rolled back: nothing was written.
            </Text>
          </Stack>
        </Alert>
      ) : null}
    </Stack>
  );
}

export function ApprovalPanel({
  c,
  me,
  view,
  approvals,
}: {
  c: CaseDetail;
  me: Me;
  view: PlanView | null | undefined;
  approvals: ApprovalsView | null | undefined;
}) {
  const decide = useDecideApproval(c.caseId);
  const [decision, setDecision] = useState<'approve' | 'reject' | null>(null);
  const [comment, setComment] = useState('');
  const [key, setKey] = useState('');
  const plan = view?.plan;
  const awaiting = c.state === 'awaiting_approval';
  const write = plan?.disposition === 'resend';
  const why = !me.approver
    ? 'Deciding needs the approver role: sign in as approver'
    : !awaiting
      ? `The case is ${humanize(c.state).toLowerCase()}, not awaiting approval`
      : !plan
        ? 'There is no plan to decide on'
        : '';
  const policy = view?.gateDecisions?.at(-1)?.policyVersion ?? '';
  // A re-plan revokes the earlier approval: only one that still stands is shown as the decision.
  const latest = approvals?.approvals?.filter((a) => !a.revoked).at(-1);
  const revoked = !latest && Boolean(approvals?.approvals?.some((a) => a.revoked));

  const openDialog = (d: 'approve' | 'reject') => {
    setDecision(d);
    setComment('');
    setKey(newIdempotencyKey());
    decide.reset();
  };
  const submit = () => {
    if (!decision || !plan) return;
    decide.mutate(
      {
        decision: { decision, planDigest: plan.digest, expectedVersion: c.version, comment },
        idempotencyKey: key,
      },
      {
        onSuccess: () => {
          setDecision(null);
          notifications.show({
            color: decision === 'approve' ? 'teal' : 'gray',
            title: decision === 'approve' ? 'Approved' : 'Rejected',
            message:
              decision === 'approve'
                ? 'The receiver is read again and the gate checks the dispatch.'
                : 'Nothing will be sent.',
          });
        },
      },
    );
  };
  const stale = decide.error && isApiError(decide.error) && decide.error.isConflict;

  return (
    <Section
      id="approval"
      title="Approval"
      note="A person approves exactly this plan. The approval binds the plan digest, the evidence snapshot, the gate's policy and the receiver version; if any of them changes before dispatch, it no longer authorises the write."
      aside={
        latest ? (
          <Badge color={latest.decision === 'approved' ? 'teal' : 'red'} style={{ textTransform: 'none' }}>
            {latest.decision === 'approved'
              ? `Approved by ${latest.approver}`
              : `Rejected by ${latest.approver}`}
          </Badge>
        ) : awaiting ? (
          <Badge color="yellow" style={{ textTransform: 'none' }}>
            Waiting for an approver
          </Badge>
        ) : revoked ? (
          <Badge color="gray" style={{ textTransform: 'none' }}>
            Earlier approval revoked
          </Badge>
        ) : null
      }
    >
      {!write && plan ? <NotYet>No approval needed: the plan writes nothing.</NotYet> : null}
      {write || awaiting ? (
        <Stack gap="sm">
          <KeyValueList
            rows={[
              [
                'Plan digest',
                <Digest key="p" value={latest?.planDigest || plan?.digest} label="plan digest" />,
              ],
              [
                'Evidence snapshot',
                latest?.snapshotDigest ? (
                  <Digest key="s" value={latest.snapshotDigest} label="snapshot digest" />
                ) : (
                  ''
                ),
              ],
              ['Gate policy', latest?.policyVersion || policy],
              ['Receiver version', String(latest?.expectedVersion ?? plan?.expectedVersion ?? '')],
              ['Valid until', latest?.expiresAt ? <Timestamp key="e" iso={latest.expiresAt} /> : ''],
              ['Comment', latest?.comment ?? ''],
            ]}
          />
          {awaiting ? (
            <Group gap="sm">
              <Tooltip label={why || 'Approve exactly this plan'} disabled={!why}>
                <span>
                  <Button
                    color="teal"
                    leftSection={<IconCheck size={16} />}
                    disabled={!!why}
                    onClick={() => openDialog('approve')}
                  >
                    Approve…
                  </Button>
                </span>
              </Tooltip>
              <Tooltip label={why || 'Reject the plan: nothing will be sent'} disabled={!why}>
                <span>
                  <Button
                    color="red"
                    variant="light"
                    leftSection={<IconX size={16} />}
                    disabled={!!why}
                    onClick={() => openDialog('reject')}
                  >
                    Reject…
                  </Button>
                </span>
              </Tooltip>
            </Group>
          ) : null}
          <BlindResendPreview c={c} me={me} />
          {approvals?.tasks?.length ? (
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
                  {approvals.tasks.map((t) => (
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
        </Stack>
      ) : null}
      <Modal
        opened={decision !== null}
        onClose={() => setDecision(null)}
        title={
          decision === 'approve'
            ? `Approve plan v${plan?.version ?? ''}`
            : `Reject plan v${plan?.version ?? ''}`
        }
        size="lg"
      >
        {plan ? (
          <Stack gap="sm">
            <Text size="sm">
              {decision === 'approve'
                ? `You approve exactly this: ${humanize(plan.actionType || 'resend').toLowerCase()} the ${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''} for ${c.encounterId}, conditional on receiver version ${String(plan.expectedVersion)}.`
                : 'You reject the plan: nothing is sent to the ward, and the case closes as blocked for a person to take further.'}
            </Text>
            <KeyValueList
              rows={[
                ['Plan digest', <Digest key="p" value={plan.digest} label="plan digest" />],
                ['Case version', String(c.version)],
              ]}
            />
            <Textarea
              label="Comment"
              description="Recorded with your decision"
              autosize
              minRows={2}
              value={comment}
              onChange={(e) => setComment(e.currentTarget.value)}
            />
            {decide.error ? (
              <Alert color="red" variant="light" role="alert">
                {stale
                  ? 'The plan or the case changed since this page loaded: close this and review it again.'
                  : describeError(decide.error)}
              </Alert>
            ) : null}
            <Group justify="flex-end" gap="sm">
              <Button variant="default" onClick={() => setDecision(null)}>
                Cancel
              </Button>
              <Button
                color={decision === 'approve' ? 'teal' : 'red'}
                loading={decide.isPending}
                onClick={submit}
                disabled={!!stale}
              >
                {decision === 'approve' ? 'Approve this plan' : 'Reject this plan'}
              </Button>
            </Group>
          </Stack>
        ) : null}
      </Modal>
    </Section>
  );
}
