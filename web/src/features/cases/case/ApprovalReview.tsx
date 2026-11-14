import { Alert, Button, Group, Paper, Stack, Text, Textarea, VisuallyHidden } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArrowDown } from '@tabler/icons-react';
import { useEffect, useId, useRef, useState } from 'react';
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
import { formatZoned, humanize, shortDigest } from '@/lib/format';
import { ApprovalChangeRows } from './ApprovalChangeRows';
import { fhirSummary, kindOfPlan, receiverKind } from './derive';
import { PlanHeadline } from './PlanHeadline';
import { decisionLabels, planWords } from './planAction';
import { receiverNoun } from './receiver';
import { useReadCurrentReview } from './readCurrent';
import { readBehind, replacedWords, whatChanged, type ReviewedState } from './staleReview';
import { WhatChanged } from './WhatChanged';

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
  /**
   * What the review this one replaces had read, when it was opened from a stopped review's "Review current plan": it
   * says what changed and why that decision was not recorded. Nothing else of that review carries over: no comment, no
   * key, no press.
   */
  replaces?: ReviewedState;
}

/** A review whose decision is no longer recorded: why, as the page saw it, and as the server refused it. */
const MOVED_WORDS = "The plan or the case changed since you opened this, so this decision can't be recorded.";
const STALE_WORDS =
  'Approval no longer valid: the plan or the case changed since you opened this, so this decision was not recorded.';

/** What a decision is bound to, said beside its controls: the plan, its encounter, its digest and the case version. */
function bindingLine(opened: OpenedReview, encounter: string): string {
  return `Bound to plan v${opened.view.plan.version}${encounter ? ` for encounter ${encounter}` : ''} (digest ${shortDigest(opened.view.plan.digest) || 'none'}) and case version ${opened.c.version}: a change to either stops it.`;
}

/**
 * The review of the exact plan, and the one place a decision on it is sent from: the case's action button, "What needs
 * you now" and the Approval section's own buttons all open this dialog. It leads with the plan's action in plain
 * words, then shows what the evidence read at the receiver and what releasing this plan is expected to leave, says
 * what the decision does (for real on a live system, in this browser only in the trial), and names the case, the
 * patient and what the decision binds (the plan digest and the case version). The controls never come into view before
 * the action, its expected effect and what the decision does: on a screen too short for all of them, the controls
 * follow those three (`.review-rest` in styles.css). The other decision is one press away ("Reject instead"), and still
 * needs its own confirming press. Opening, switching and cancelling send nothing, and while a decision is being sent
 * the dialog can't be closed, so its answer is always shown. A review the case moved under (a stale plan or case
 * version, seen by the page or refused by the server) stops for good, keeps its refusal and says what changed, and
 * offers "Review current plan": the case is read again and a new review opens on it, with its own confirming press.
 */
export function ApprovalReview({
  c,
  view,
  snapshot,
  review,
  onClose,
  onSwitch,
  onReopen,
}: {
  /** The case, its plan and its evidence as the page reads them now: a change since the review opened stops it. */
  c: CaseDetail;
  view: PlanView | null | undefined;
  snapshot: Snapshot | null | undefined;
  /** The open review, or null when the dialog is closed. */
  review: OpenedReview | null;
  onClose: () => void;
  /** Turns the open review to the other decision, on the same plan. */
  onSwitch: (decision: Decision) => void;
  /** Opens a new review on the case as just read, in place of one that was stopped. */
  onReopen: (next: Omit<OpenedReview, 'n'>) => void;
}) {
  // The dialog keeps the last review's words while it animates closed: approve must not flash as a red Reject
  const [shown, setShown] = useState<OpenedReview | null>(review);
  if (review && review !== shown) setShown(review);
  // A decision on its way holds the dialog open: closed, it could not say "Approved by ..." or why it was refused
  const [sending, setSending] = useState(false);
  const labels = decisionLabels(shown?.view.plan);
  return (
    <ConfirmModal
      opened={review !== null}
      onClose={onClose}
      locked={sending}
      title={
        shown
          ? `${shown.decision === 'reject' ? labels.reject : labels.approve}: plan v${shown.view.plan.version}`
          : ''
      }
      size="lg"
    >
      {/* Said once a review replaces a stopped one, in a region that was there before, so a screen reader reads it */}
      <VisuallyHidden role="status" aria-live="polite" data-testid="review-status">
        {review && shown?.replaces
          ? `Plan v${shown.view.plan.version} is open for review. Nothing is decided until you confirm it.`
          : ''}
      </VisuallyHidden>
      {shown ? (
        // One body per opening: its comment, its idempotency key and its request start afresh each time
        <ReviewBody
          key={shown.n}
          c={c}
          view={view}
          snapshot={snapshot}
          opened={shown}
          live={review !== null}
          onClose={onClose}
          onSwitch={onSwitch}
          onSending={setSending}
          onReopen={onReopen}
        />
      ) : null}
    </ConfirmModal>
  );
}

function ReviewBody({
  c,
  view,
  snapshot,
  opened,
  live,
  onClose,
  onSwitch,
  onSending,
  onReopen,
}: {
  c: CaseDetail;
  view: PlanView | null | undefined;
  snapshot: Snapshot | null | undefined;
  opened: OpenedReview;
  /** Whether the dialog is open, not closing: only an open review can be stopped by a change under it. */
  live: boolean;
  onClose: () => void;
  onSwitch: (decision: Decision) => void;
  /** Says when a decision is on its way, and when it has been answered: the dialog stays open in between. */
  onSending: (sending: boolean) => void;
  onReopen: (next: Omit<OpenedReview, 'n'>) => void;
}) {
  const decide = useDecideApproval(c.caseId);
  const [comment, setComment] = useState('');
  const [key, setKey] = useState(newIdempotencyKey);
  const body = useRef<HTMLDivElement>(null);
  const { decision } = opened;
  const approving = decision === 'approve';
  const labels = decisionLabels(opened.view.plan);
  // A FHIR case is approved on the Encounter's ETag as read: the evidence's route.kind, else the FHIR gate's policy
  const fhir = (receiverKind(opened.snapshot) ?? kindOfPlan(opened.view)) === 'fhir_r4';
  const etag = fhirSummary(opened.snapshot)?.encounter?.etag ?? '';
  // A decision sent or answered moves the case by itself: only a change before that stops the dialog. A read older
  // than the review (the page catching up with the fresh read a replacing review opened on) is no change
  const moved =
    live &&
    !decide.isPending &&
    !decide.isSuccess &&
    !readBehind(opened, c, view) &&
    (view?.plan?.digest !== opened.view.plan.digest || c.version !== opened.c.version);
  // Only a stale plan or case version asks for a fresh look; any other refusal (a 403 naming the Workflow role, a 409
  // naming who the task is assigned to) is shown as the server worded it.
  const stale = !!decide.error && isApiError(decide.error) && decide.error.code === 'stale_version';
  // Once stopped, the review stays stopped, closing included: its decision can't be sent again, and the reason it
  // became invalid stays to be read until the person moves on
  const [stopped, setStopped] = useState(false);
  if ((moved || stale) && !stopped) setStopped(true);
  // A replacing review starts at its note, which says what it replaces: it is read from the dialog's top (where the
  // stopped review's scroll would otherwise leave it under the title), and keyboard focus follows it there
  const note = useRef<HTMLDivElement>(null);
  const noteTitle = useId();
  useEffect(() => {
    if (!opened.replaces) return;
    note.current?.closest('.mantine-Modal-content')?.scrollTo?.({ top: 0 });
    note.current?.focus({ preventScroll: true });
  }, [opened.replaces]);
  // The dialog is held open from the confirming press (said there, before the request is even pending) until the
  // answer: a decision that lands with the dialog closed would land unannounced
  useEffect(() => {
    onSending(decide.isPending);
    return () => onSending(false);
  }, [decide.isPending, onSending]);
  // Whether the controls are still wholly below the dialog's foot (a short screen, a plan with notes): a line at the
  // foot then says the decision is further down, so a screen that happens to end on a whole sentence never reads as
  // a dialog without one
  const controls = useRef<HTMLDivElement>(null);
  const [below, setBelow] = useState(false);
  useEffect(() => {
    const el = controls.current;
    if (!el || typeof IntersectionObserver === 'undefined') return undefined;
    const watch = new IntersectionObserver(([entry]) => setBelow(!entry.isIntersecting), {
      root: el.closest('.mantine-Modal-content'),
    });
    watch.observe(el);
    return () => watch.disconnect();
  }, []);
  const encounter = opened.c.encounterId && opened.c.encounterId !== '-' ? opened.c.encounterId : '';
  if (stopped)
    return (
      <StoppedReview
        c={c}
        view={view}
        snapshot={snapshot}
        opened={opened}
        why={stale ? STALE_WORDS : MOVED_WORDS}
        binding={bindingLine(opened, encounter)}
        live={live}
        onClose={onClose}
        onReopen={onReopen}
      />
    );
  const submit = () => {
    if (moved) return;
    onSending(true);
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
        // Answered either way, the dialog can be closed again
        onSettled: () => onSending(false),
      },
    );
  };
  return (
    <Stack gap="sm" ref={body}>
      {/* A review that replaces a stopped one says so first: why that decision was not recorded and what changed */}
      {opened.replaces ? (
        <Paper
          withBorder
          p="sm"
          radius="md"
          ref={note}
          tabIndex={-1}
          role="group"
          aria-labelledby={noteTitle}
          data-testid="review-replaces"
        >
          <Stack gap={6}>
            <Text size="sm" fw={600} id={noteTitle}>
              {`Now reviewing the current plan, v${opened.view.plan.version}`}
            </Text>
            <Text size="sm">
              {`${replacedWords(opened.replaces, opened)} Nothing is decided until you confirm it.`}
            </Text>
            <WhatChanged rows={whatChanged(opened.replaces, opened)} />
          </Stack>
        </Paper>
      ) : null}
      {/* What is decided, first: the plan's own action, as every other place on the page names it */}
      <PlanHeadline words={planWords(opened.view.plan, opened.c, opened.snapshot)} />
      {/* Then what releasing it is expected to leave at the receiver, with what the reader should know of it */}
      {approving ? <ApprovalChangeRows view={opened.view} c={opened.c} snapshot={opened.snapshot} /> : null}
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
      {/* A FHIR case is approved on the Encounter's ETag as read, with no dry run and no resend of the HL7 message */}
      {approving && fhir ? (
        <Text size="sm" data-testid="fhir-approval">
          {`Shutter sends this update with If-Match on the version read at ${formatZoned(opened.snapshot?.takenAt)} (ETag ${etag}). This server software refused a changed version when it was measured. No dry run exists for this receiver. After this update, do not resend the original HL7 message from the engine.`}
        </Text>
      ) : null}
      {/* The rest scrolls under the controls, which are sticky inside this block and so never rise over the three
          above: the confirming press comes into view only after them */}
      <Stack gap="sm" className="review-rest">
        <KeyValueList
          rows={[
            ['Case', opened.c.caseId],
            [
              'Patient',
              `${opened.c.patientId}${opened.c.patientIdAuthority ? ` (${opened.c.patientIdAuthority})` : ''}`,
            ],
            ['Encounter', encounter],
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
        <Stack gap="sm" className="review-actions" ref={controls}>
          {/* What the decision is bound to, in view beside its controls however far the facts above are scrolled */}
          <Text size="xs" c="dimmed" data-testid="review-binding">
            {bindingLine(opened, encounter)}
          </Text>
          {decide.error ? (
            <Alert color="red" variant="light" role="alert">
              {describeError(decide.error)}
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
                disabled={moved}
              >
                {approving ? labels.approve : labels.reject}
              </Button>
            </Group>
          </Group>
        </Stack>
      </Stack>
      {below ? (
        <div className="review-more" aria-hidden data-testid="review-more">
          <Text size="sm" fw={600}>
            <IconArrowDown size={16} stroke={2} />
            The decision is below
          </Text>
        </div>
      ) : null}
    </Stack>
  );
}

/**
 * A review the case moved under, stopped for good: the plan the person read, why the decision was not recorded (in
 * the words it was refused with) and what changed, as far as the page has read it. No decision can be pressed here.
 * "Review current plan" reads the case again and opens a new review on what it reads, which needs its own confirming
 * press; a read that fails says so and offers to try again, and a case with nothing left to decide says that, with
 * neither a review nor a decision to press.
 */
function StoppedReview({
  c,
  view,
  snapshot,
  opened,
  why,
  binding,
  live,
  onClose,
  onReopen,
}: {
  c: CaseDetail;
  view: PlanView | null | undefined;
  snapshot: Snapshot | null | undefined;
  opened: OpenedReview;
  why: string;
  binding: string;
  live: boolean;
  onClose: () => void;
  onReopen: (next: Omit<OpenedReview, 'n'>) => void;
}) {
  const read = useReadCurrentReview(c.caseId);
  const again = useRef<HTMLButtonElement>(null);
  const cancel = useRef<HTMLButtonElement>(null);
  // A read answered after the dialog closed opens nothing
  const open = useRef(live);
  useEffect(() => {
    open.current = live;
  }, [live]);
  // The change as far as the page has read it: none until its reads have caught up with the refusal
  const rows = readBehind(opened, c, view) ? [] : whatChanged(opened, { c, view, snapshot });
  const now = read.data;
  const gone = now && !(now.c.state === 'awaiting_approval' && now.view?.plan) ? now.c : null;
  // The controls the person was at are gone: keyboard focus moves to the next step, unless it is somewhere it can stay
  useEffect(() => {
    if (!document.activeElement || document.activeElement === document.body) again.current?.focus();
  }, []);
  // A read that failed gives focus back to the press that tries again; with nothing to decide, to Cancel
  useEffect(() => {
    if (read.isError) again.current?.focus();
  }, [read.isError]);
  useEffect(() => {
    if (gone) cancel.current?.focus();
  }, [gone]);
  const reviewCurrent = () =>
    read.mutate(undefined, {
      onSuccess: (fresh) => {
        if (!open.current || fresh.c.state !== 'awaiting_approval' || !fresh.view?.plan) return;
        onReopen({
          decision: opened.decision,
          c: fresh.c,
          view: fresh.view,
          snapshot: fresh.snapshot,
          replaces: { c: opened.c, view: opened.view, snapshot: opened.snapshot },
        });
      },
    });
  return (
    <Stack gap="sm" data-testid="review-stopped">
      {/* The plan the person read, so the refusal and the change are read against it */}
      <PlanHeadline words={planWords(opened.view.plan, opened.c, opened.snapshot)} />
      <Alert color="red" variant="light" role="alert" data-testid="review-refusal">
        {gone ? why : `${why} Review the current plan to decide again.`}
      </Alert>
      {rows.some((r) => r.changed) ? <WhatChanged rows={rows} /> : null}
      <Text size="xs" c="dimmed" data-testid="review-binding">
        {binding}
      </Text>
      {read.isError ? (
        <Alert color="red" variant="light" role="alert" data-testid="review-current-failed">
          {`The current plan could not be read: ${describeError(read.error)}. Nothing was decided; try again, or cancel.`}
        </Alert>
      ) : null}
      {gone ? (
        <Alert color="gray" variant="light" role="alert" data-testid="review-current-gone">
          {gone.state === 'awaiting_approval'
            ? 'The case has no plan to decide on now. Nothing was decided in this review.'
            : `The case is no longer waiting for a decision: it is ${humanize(gone.state).toLowerCase()} now. Nothing was decided in this review.`}
        </Alert>
      ) : null}
      <Group justify="flex-end" gap="sm" wrap="wrap">
        <Button variant="default" ref={cancel} onClick={onClose}>
          Cancel
        </Button>
        {gone ? null : (
          <Button ref={again} loading={read.isPending} onClick={reviewCurrent}>
            Review current plan
          </Button>
        )}
      </Group>
    </Stack>
  );
}
