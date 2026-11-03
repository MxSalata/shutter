import { Alert, Button, Group, Stack, Table, Text, Textarea, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCheck, IconEye, IconX } from '@tabler/icons-react';
import { useState } from 'react';
import { usePreviewBlindResend, useDecideApproval } from '@/api/hooks';
import { newIdempotencyKey } from '@/api/client';
import { resolveCan } from '@/api/can';
import type { ApprovalsView, CaseDetail, Me, PlanView } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { byEnv } from '@/env/copy';
import { Digest } from '@/components/Digest';
import { ConfirmModal } from '@/components/ConfirmModal';
import { TechDetail } from '@/components/TechDetail';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { StackTable } from '@/components/StackTable';
import { APPROVALS } from '@/lib/status';
import { describeError, isApiError } from '@/lib/errors';
import { asObject } from '@/lib/json';
import { humanize } from '@/lib/format';
import { approvalsByPlan, earlierApprovalText } from './receipt';
import { NotYet, Section } from './Section';
import { capitalReceiverNoun, receiverNoun } from './receiver';

function BlindResendPreview({ c, me }: { c: CaseDetail; me: Me }) {
  const preview = usePreviewBlindResend(c.caseId);
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(c.state);
  const why = !me.operator ? 'The preview needs the operator role' : closed ? 'The case is closed' : '';
  const r = preview.data;
  const after = asObject(r?.encounterAfter);
  // Only a dry run the receiver answered as one was rolled back; one it applied is now in effect.
  const rolledBack = !!r && !r.applied && (r.outcome === 'would_apply' || r.outcome === 'would_not_apply');
  const checked = r?.checkedAgainst;
  return (
    <Stack gap="xs">
      <Group gap="sm">
        <Tooltip
          label={
            why ||
            `Ask ${receiverNoun(c.receiver)} what the original message would do if it were simply sent again, with no version check. Nothing is written.`
          }
          multiline
          maw={320}
        >
          <span>
            <Button
              variant="default"
              size="xs"
              leftSection={<IconEye size={14} />}
              disabled={!!why}
              loading={preview.isPending}
              onClick={() => preview.mutate()}
            >
              What would resending now do?
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
          color={r.applied ? 'red' : r.wouldApply ? 'yellow' : 'gray'}
          variant="light"
          title={
            r.applied
              ? 'The receiver applied the preview'
              : r.wouldApply
                ? 'Resending now, with no version check, would apply'
                : 'Resending now, with no version check, would be refused'
          }
        >
          <Stack gap={4}>
            {after ? (
              <Text size="sm">
                Afterwards {receiverNoun(c.receiver)} would hold {humanize(String(after.state ?? ''))}
                {after.ward ? ` in ${String(after.ward)}` : ''}, version {String(after.version ?? '')}.
              </Text>
            ) : null}
            {r.reason ? <Text size="sm">Reason: {humanize(r.reason)}</Text> : null}
            {r.note ? <Text size="sm">{r.note}</Text> : null}
            {checked && checked.version !== null ? (
              <Text size="sm">
                Checked against version {checked.version}
                {checked.epoch !== null ? `, epoch ${checked.epoch}` : ''}; the preview was conditional on no
                version.
              </Text>
            ) : null}
            {rolledBack ? (
              <Text size="xs" c="dimmed">
                {capitalReceiverNoun(c.receiver)}&apos;s dry run, rolled back: nothing was written.
              </Text>
            ) : null}
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
  const why = !resolveCan(me).approve
    ? 'Deciding needs the approver role: sign in as approver'
    : !awaiting
      ? `The case is ${humanize(c.state).toLowerCase()}, not waiting for approval`
      : !plan
        ? 'There is no plan to decide on'
        : '';
  const policy = view?.gateDecisions?.at(-1)?.policyVersion ?? '';
  // Only the current plan's approval that still stands is shown as the decision; a re-plan revokes the earlier
  // plan's, which is history.
  const { current, earlier } = approvalsByPlan(approvals, view);
  const latest = current.filter((a) => !a.revoked).at(-1);
  const underIncident = Boolean(latest?.incidentPlanDigest);
  const revoked = !latest && current.some((a) => a.revoked);
  const history = earlierApprovalText(earlier, view);

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
        onSuccess: (reply) => {
          setDecision(null);
          // In the trial the page itself plays out what came next, and announces it once
          if (TRIAL && decision === 'approve') return;
          const by = reply?.approver ? ` by ${reply.approver}` : '';
          notifications.show({
            color: decision === 'approve' ? 'blue' : 'gray',
            title:
              decision === 'approve'
                ? `Approved${by}`
                : byEnv({ live: `Rejected${by}`, trial: 'Rejected in the trial' }),
            message:
              decision !== 'approve'
                ? 'Nothing will be sent.'
                : 'The receiver is read again and the gate checks the dispatch.',
          });
        },
      },
    );
  };
  // Only a stale plan or case version asks for a fresh look; any other refusal (a 403 naming the Workflow role, a 409
  // naming who the task is assigned to) is shown as the server worded it.
  const stale = decide.error && isApiError(decide.error) && decide.error.code === 'stale_version';

  return (
    <Section
      id="approval"
      title="Approval"
      note="Every write passes the gate first; then a person, or the site's written policy, releases exactly this plan."
      aside={
        latest ? (
          latest.decision !== 'approved' ? (
            <StatusBadge {...APPROVALS.rejected} label={`Rejected by ${latest.approver}`} />
          ) : latest.approver === 'policy' ? (
            <StatusBadge {...APPROVALS.policy} />
          ) : (
            <StatusBadge
              {...APPROVALS.approved}
              label={`Approved by ${latest.approver}${underIncident ? " under the incident's approval" : ''}`}
            />
          )
        ) : awaiting ? (
          <StatusBadge {...APPROVALS.awaiting} />
        ) : revoked ? (
          <StatusBadge {...APPROVALS.revoked} label="Approval no longer valid" />
        ) : !write && plan ? (
          <StatusBadge {...APPROVALS.not_required} />
        ) : null
      }
    >
      <TechDetail kind="explain" label="What an approval binds">
        <Text size="sm" maw="68ch">
          The release binds the plan digest, the evidence snapshot, the gate&apos;s policy and the receiver
          version; if any of them changes before dispatch, it no longer authorises the write, and the gate
          checks again at dispatch.
        </Text>
      </TechDetail>
      {!write && plan ? <NotYet>No approval needed: the plan writes nothing.</NotYet> : null}
      {history ? (
        <Group gap="xs" wrap="wrap">
          <StatusBadge {...APPROVALS.revoked} tone="neutral" label="Earlier plan" />
          <Text size="sm">{`${history}. It does not release the current plan.`}</Text>
        </Group>
      ) : null}
      {write || awaiting ? (
        <Stack gap="sm">
          {TRIAL && awaiting ? (
            <Alert color="blue" variant="light" title="Held for you to decide">
              This recorded case waits here for you. Approve it and the recording plays on: the fix goes out
              and the receiving system confirms it. Reject it and it closes as blocked.
            </Alert>
          ) : null}
          <KeyValueList
            rows={[
              [
                'Plan digest',
                <Stack key="p" gap={0}>
                  <Digest value={latest?.planDigest || plan?.digest} label="plan digest" />
                  <Text size="xs" c="dimmed">
                    A fingerprint of the exact plan: any change to it gives another digest.
                  </Text>
                </Stack>,
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
              [
                'Incident plan digest',
                latest?.incidentPlanDigest ? (
                  <Digest key="i" value={latest.incidentPlanDigest} label="incident plan digest" />
                ) : (
                  ''
                ),
              ],
              [
                'Approved as',
                latest?.incidentPlanDigest
                  ? `${latest.boundEntry ?? ''} · ${humanize(latest.boundOutcome ?? '')}`
                  : '',
              ],
            ]}
          />
          {awaiting ? (
            <Stack gap={4}>
              <Group gap="sm">
                <Tooltip label={why || 'Approve exactly this plan'} disabled={!why}>
                  <span>
                    <Button
                      leftSection={<IconCheck size={16} />}
                      disabled={!!why}
                      onClick={() => openDialog('approve')}
                      data-tour-action="approve-plan"
                    >
                      Approve plan
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
                      Reject plan
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
          <BlindResendPreview c={c} me={me} />
          {approvals?.tasks?.length ? (
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
                  {approvals.tasks.map((t) => (
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
        </Stack>
      ) : null}
      <ConfirmModal
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
            {/* What the action does, first: for real on a live system, in this browser only in the trial */}
            <Text size="sm" fw={600} data-testid="confirm-consequence">
              {decision === 'approve'
                ? byEnv({
                    live: `This sends the fix to ${receiverNoun(c.receiver)}, for real. The receiver is read again and the gate checks the dispatch.`,
                    trial:
                      'Go ahead. You will see what happened next in the recording: the fix goes out and the receiving system confirms it. Nothing leaves this browser, and a reload starts the recording afresh.',
                  })
                : byEnv({
                    live: `Nothing is sent to ${receiverNoun(c.receiver)}: the case closes as blocked for a person to take further.`,
                    trial:
                      'Nothing is sent. The case closes as blocked, in this browser only, until a reload starts the recording afresh.',
                  })}
            </Text>
            {decision === 'approve' ? (
              <Text size="sm">
                {`You approve exactly this: ${humanize(plan.actionType || 'resend').toLowerCase()} the ${humanize(c.event).toLowerCase()}${c.ward ? ` to ${c.ward}` : ''} for ${c.encounterId}, conditional on receiver version ${String(plan.expectedVersion)}.`}
              </Text>
            ) : null}
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
                  ? 'Approval no longer valid: the plan or the case changed since this page loaded, so this decision was not recorded. Close this and review the new plan.'
                  : describeError(decide.error)}
              </Alert>
            ) : null}
            <Group justify="flex-end" gap="sm">
              <Button variant="default" onClick={() => setDecision(null)}>
                Cancel
              </Button>
              <Button
                color={decision === 'approve' ? undefined : 'red'}
                loading={decide.isPending}
                onClick={submit}
                disabled={!!stale}
              >
                {decision === 'approve' ? 'Approve this plan' : 'Reject this plan'}
              </Button>
            </Group>
          </Stack>
        ) : null}
      </ConfirmModal>
    </Section>
  );
}
