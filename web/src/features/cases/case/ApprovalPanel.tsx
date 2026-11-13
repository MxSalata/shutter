import { Alert, Button, Group, Stack, Table, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconEye, IconX } from '@tabler/icons-react';
import { usePreviewBlindResend } from '@/api/hooks';
import { resolveCan } from '@/api/can';
import type { ApprovalsView, CaseDetail, Me, PlanView } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { toBecomeApprover } from '@/env/copy';
import { Digest } from '@/components/Digest';
import { TechDetail } from '@/components/TechDetail';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { StackTable } from '@/components/StackTable';
import { APPROVALS } from '@/lib/status';
import { describeError } from '@/lib/errors';
import { asObject } from '@/lib/json';
import { humanize } from '@/lib/format';
import type { ApprovalEvidence } from './approvalChange';
import { ApprovalChangeRows } from './ApprovalChangeRows';
import type { Decision } from './ApprovalReview';
import { PlanHeadline } from './PlanHeadline';
import { decisionLabels, planWords } from './planAction';
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

/**
 * The Approval section of the decision step: the plan's action as its headline, what the evidence read at the receiver
 * and what releasing the plan is expected to leave, then the two decisions, each named for the action ("Approve the
 * resend"). Both open the review of the exact plan (`ApprovalReview`, which the case page holds, so the case's action
 * button opens the same one); nothing is sent from here. What an approval binds, in digests and versions, is one
 * click away under "Approval details", open in Technical.
 */
export function ApprovalPanel({
  c,
  me,
  view,
  approvals,
  snapshot,
  onDecide,
}: {
  c: CaseDetail;
  me: Me;
  view: PlanView | null | undefined;
  approvals: ApprovalsView | null | undefined;
  /** The evidence, for what the receiver held when it was read. */
  snapshot: ApprovalEvidence;
  /** Opens the review of the exact plan on this decision. */
  onDecide: (decision: Decision) => void;
}) {
  const plan = view?.plan;
  const awaiting = c.state === 'awaiting_approval';
  const write = plan?.disposition === 'resend';
  const why = !resolveCan(me).approve
    ? `Deciding needs the approver role: ${toBecomeApprover()}`
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
  const labels = decisionLabels(plan);

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
      {!write && plan ? <NotYet>No approval needed: the plan writes nothing.</NotYet> : null}
      {history ? (
        <Group gap="xs" wrap="wrap">
          <StatusBadge {...APPROVALS.revoked} tone="neutral" label="Earlier plan" />
          <Text size="sm">{`${history}. It does not release the current plan.`}</Text>
        </Group>
      ) : null}
      {write || awaiting ? (
        <Stack gap="sm">
          {/* What is to be decided, while it waits: the plan's action, and what releasing it is expected to leave */}
          {awaiting && plan ? <PlanHeadline words={planWords(plan, c, snapshot)} /> : null}
          {awaiting && view ? <ApprovalChangeRows view={view} c={c} snapshot={snapshot} /> : null}
          {TRIAL && awaiting ? (
            <Alert color="blue" variant="light" title="Held for you to decide">
              This recorded case waits here for you. Approve it and the recording plays on: the fix goes out
              and the receiving system confirms it. Reject it and it stops as blocked, for a person to take
              further.
            </Alert>
          ) : null}
          {awaiting ? (
            <Stack gap={4} data-tour="case-approve">
              <Group gap="sm">
                <Tooltip label={why || 'Review and approve exactly this plan'} disabled={!why}>
                  <span>
                    <Button
                      leftSection={<IconCheck size={16} />}
                      disabled={!!why}
                      onClick={() => onDecide('approve')}
                      data-tour-action="approve-plan"
                    >
                      {labels.approve}
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
                      onClick={() => onDecide('reject')}
                    >
                      {labels.reject}
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
          {/* The decision in words, once there is one */}
          {latest && (latest.expiresAt || latest.comment || latest.incidentPlanDigest) ? (
            <KeyValueList
              rows={[
                ['Valid until', latest.expiresAt ? <Timestamp key="e" iso={latest.expiresAt} /> : ''],
                ['Comment', latest.comment ?? ''],
                [
                  'Approved as',
                  latest.incidentPlanDigest
                    ? `${latest.boundEntry ?? ''} · ${humanize(latest.boundOutcome ?? '')}`
                    : '',
                ],
              ]}
            />
          ) : null}
          <TechDetail kind="data" label="Approval details">
            <Stack gap="xs">
              <Text size="sm" maw="68ch">
                The release binds the plan digest, the evidence snapshot, the gate&apos;s policy and the
                receiver version; if any of them changes before dispatch, it no longer authorises the write,
                and the gate checks again at dispatch.
              </Text>
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
                  [
                    'Incident plan digest',
                    latest?.incidentPlanDigest ? (
                      <Digest key="i" value={latest.incidentPlanDigest} label="incident plan digest" />
                    ) : (
                      ''
                    ),
                  ],
                ]}
              />
            </Stack>
          </TechDetail>
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
    </Section>
  );
}
