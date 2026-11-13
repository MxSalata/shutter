import { Alert, Button, Group, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useRef, useState } from 'react';
import { useDecideApproval } from '@/api/hooks';
import { newIdempotencyKey } from '@/api/client';
import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { byEnv } from '@/env/copy';
import { ConfirmModal } from '@/components/ConfirmModal';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { describeError, isApiError } from '@/lib/errors';
import { shortDigest } from '@/lib/format';
import { ApprovalChangeRows } from './ApprovalChangeRows';
import { PlanHeadline } from './PlanHeadline';
import { decisionLabels, planWords } from './planAction';
import { receiverNoun } from './receiver';

/** What a person can decide on a plan that waits for approval. */
export type Decision = 'approve' | 'reject';

/**
 * A review as it was opened: the decision it started on, and the case, the plan with its dry run and the evidence as
 * the person saw them when they opened it. The page's reads carry on under the dialog; what it shows and what it
 * sends never do, so a decision is only ever on what the person read.
 */
export interface OpenedReview {
  decision: Decision;
  c: CaseDetail;
  view: PlanView;
  snapshot: Snapshot | null | undefined;
  /** Counts the openings: each one starts with an empty comment and its own idempotency key. */
  n: number;
}

/**
 * The review of the exact plan, and the one place a decision on it is sent from: the case's action button, "What needs
 * you now" and the Approval section's own buttons all open this dialog. It leads with the plan's action in plain
 * words, says what the decision does (for real on a live system, in this browser only in the trial), shows what the
 * evidence read at the receiver and what releasing this plan is expected to leave, and names the case, the patient and
 * what the decision binds (the plan digest and the case version). The other decision is one press away ("Reject
 * instead"), and still needs its own confirming press. Opening, switching and cancelling send nothing.
 */
export function ApprovalReview({
  c,
  view,
  review,
  onClose,
  onSwitch,
}: {
  /** The case and its plan as the page reads them now: a change since the review opened stops the decision. */
  c: CaseDetail;
  view: PlanView | null | undefined;
  /** The open review, or null when the dialog is closed. */
  review: OpenedReview | null;
  onClose: () => void;
  /** Turns the open review to the other decision, on the same plan. */
  onSwitch: (decision: Decision) => void;
}) {
  // The dialog keeps the last review's words while it animates closed: approve must not flash as a red Reject
  const [shown, setShown] = useState<OpenedReview | null>(review);
  if (review && review !== shown) setShown(review);
  const labels = decisionLabels(shown?.view.plan);
  return (
    <ConfirmModal
      opened={review !== null}
      onClose={onClose}
      title={
        shown
          ? `${shown.decision === 'reject' ? labels.reject : labels.approve}: plan v${shown.view.plan.version}`
          : ''
      }
      size="lg"
    >
      {shown ? (
        // One body per opening: its comment, its idempotency key and its request start afresh each time
        <ReviewBody
          key={shown.n}
          c={c}
          view={view}
          opened={shown}
          live={review !== null}
          onClose={onClose}
          onSwitch={onSwitch}
        />
      ) : null}
    </ConfirmModal>
  );
}

function ReviewBody({
  c,
  view,
  opened,
  live,
  onClose,
  onSwitch,
}: {
  c: CaseDetail;
  view: PlanView | null | undefined;
  opened: OpenedReview;
  /** Whether the dialog is open, not closing: only an open review can be stopped by a change under it. */
  live: boolean;
  onClose: () => void;
  onSwitch: (decision: Decision) => void;
}) {
  const decide = useDecideApproval(c.caseId);
  const [comment, setComment] = useState('');
  const [key, setKey] = useState(newIdempotencyKey);
  const body = useRef<HTMLDivElement>(null);
  const { decision } = opened;
  const approving = decision === 'approve';
  const labels = decisionLabels(opened.view.plan);
  // A decision sent or answered moves the case by itself: only a change before that stops the dialog
  const moved =
    live &&
    !decide.isPending &&
    !decide.isSuccess &&
    (view?.plan?.digest !== opened.view.plan.digest || c.version !== opened.c.version);
  const submit = () => {
    if (moved) return;
    decide.mutate(
      {
        decision: {
          decision,
          planDigest: opened.view.plan.digest,
          expectedVersion: opened.c.version,
          comment,
        },
        idempotencyKey: key,
      },
      {
        onSuccess: (reply) => {
          onClose();
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
    <Stack gap="sm" ref={body}>
      {/* What is decided, first: the plan's own action, as every other place on the page names it */}
      <PlanHeadline words={planWords(opened.view.plan, opened.c, opened.snapshot)} />
      {/* Then what this decision does: for real on a live system, in this browser only in the trial */}
      <Text size="sm" fw={600} data-testid="confirm-consequence">
        {approving
          ? byEnv({
              live: `This sends the fix to ${receiverNoun(opened.c.receiver)}, for real. The receiver is read again and the gate checks the dispatch.`,
              trial:
                'Go ahead. You will see what happened next in the recording: the fix goes out and the receiving system confirms it. Nothing leaves this browser, and a reload starts the recording afresh.',
            })
          : byEnv({
              live: `Nothing is sent to ${receiverNoun(opened.c.receiver)}: the case stops as blocked for a person to take further.`,
              trial:
                'Nothing is sent. The case stops as blocked, in this browser only, until a reload starts the recording afresh.',
            })}
      </Text>
      {approving ? <ApprovalChangeRows view={opened.view} c={opened.c} snapshot={opened.snapshot} /> : null}
      <KeyValueList
        rows={[
          ['Case', opened.c.caseId],
          [
            'Patient',
            `${opened.c.patientId}${opened.c.patientIdAuthority ? ` (${opened.c.patientIdAuthority})` : ''}`,
          ],
          ['Encounter', opened.c.encounterId && opened.c.encounterId !== '-' ? opened.c.encounterId : ''],
          ['Event time', <Timestamp key="t" iso={opened.c.eventTime} />],
          ['Bed', opened.c.bed ?? ''],
          ['Why it is still due', opened.view.plan.why || opened.view.plan.summary],
          ['Plan digest', <Digest key="p" value={opened.view.plan.digest} label="plan digest" />],
          ['Case version', String(opened.c.version)],
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
      {/* The decision's controls stay in view while the review scrolls, with whatever stops them said beside them */}
      <Stack gap="sm" className="review-actions">
        {/* What the decision is bound to, in view beside its controls however far the facts above are scrolled */}
        <Text size="xs" c="dimmed" data-testid="review-binding">
          {`Bound to plan v${opened.view.plan.version} (digest ${shortDigest(opened.view.plan.digest) || 'none'}) and case version ${opened.c.version}: a change to either stops it.`}
        </Text>
        {moved ? (
          <Alert color="red" variant="light" role="alert">
            The plan or the case changed since you opened this, so this decision can&apos;t be recorded. Close
            this and review the new plan.
          </Alert>
        ) : decide.error ? (
          <Alert color="red" variant="light" role="alert">
            {stale
              ? 'Approval no longer valid: the plan or the case changed since you opened this, so this decision was not recorded. Close this and review the new plan.'
              : describeError(decide.error)}
          </Alert>
        ) : null}
        <Group justify="space-between" gap="sm" wrap="wrap">
          {/* The other decision, one press away and never sent by this press: it turns the review, which then asks
              for its own confirming press */}
          <Button
            variant="subtle"
            color={approving ? 'red' : undefined}
            disabled={decide.isPending}
            onClick={() => {
              // Another decision is another request: it never rides on a key the first one may have used
              decide.reset();
              setKey(newIdempotencyKey());
              onSwitch(approving ? 'reject' : 'approve');
              // The turned review is read from its top: its title, the action and what this decision does
              body.current?.closest('.mantine-Modal-content')?.scrollTo?.({ top: 0 });
            }}
          >
            {approving ? 'Reject instead' : 'Approve instead'}
          </Button>
          <Group gap="sm">
            <Button variant="default" onClick={onClose} disabled={decide.isPending}>
              Cancel
            </Button>
            <Button
              color={approving ? undefined : 'red'}
              loading={decide.isPending}
              onClick={submit}
              disabled={!!stale || moved}
            >
              {approving ? labels.approve : labels.reject}
            </Button>
          </Group>
        </Group>
      </Stack>
    </Stack>
  );
}
