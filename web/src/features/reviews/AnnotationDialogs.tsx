import { Alert, Button, Group, Modal, Radio, Stack, Text, Textarea, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import { useAnnotateFinding, useRemoveAnnotation } from '@/api/hooks';
import type { ReviewAnnotation, ReviewDetail, ReviewFinding } from '@/api/types';
import { DEMO } from '@/demo';
import { describeError } from '@/lib/errors';
import { expiryForApi, expiryProblem, STATUS_LABELS, subjectOf } from './review';

type Status = ReviewAnnotation['status'];

const STATUS_NOTES: Record<Status, string> = {
  intended: 'The setting is as the site wants it.',
  accepted_risk: 'The hazard is known and accepted for now.',
  false_positive: 'The check is wrong about this production.',
};

/**
 * An approver's annotation of a finding, and its removal. An annotation is a Shutter record bound to the finding's
 * code, item, setting and exact value: it applies to every review of the production and reopens the finding when the
 * value changes, it expires or it is removed. Nothing in the production changes.
 */
export function useAnnotationDialogs(review: ReviewDetail) {
  const annotate = useAnnotateFinding(review.reviewId);
  const remove = useRemoveAnnotation();
  const [marking, setMarking] = useState<ReviewFinding | null>(null);
  const [removing, setRemoving] = useState<ReviewFinding | null>(null);
  const [status, setStatus] = useState<Status>('intended');
  const [reason, setReason] = useState('');
  const [expires, setExpires] = useState('');
  const [key, setKey] = useState('');

  const mark = (f: ReviewFinding) => {
    setMarking(f);
    setStatus('intended');
    setReason('');
    setExpires('');
    setKey(newIdempotencyKey());
    annotate.reset();
  };
  const unmark = (f: ReviewFinding) => {
    setRemoving(f);
    remove.reset();
  };
  const problem = expiryProblem(expires);
  const submit = () => {
    if (!marking || !reason.trim() || problem) return;
    annotate.mutate(
      {
        annotation: {
          findingId: marking.id,
          status,
          reason: reason.trim(),
          ...(expires.trim() ? { expiresAt: expiryForApi(expires) } : {}),
        },
        idempotencyKey: key,
      },
      {
        onSuccess: () => {
          setMarking(null);
          notifications.show({
            color: 'blue',
            title: `Marked as ${STATUS_LABELS[status].toLowerCase()}`,
            message: 'Bound to this exact value: the finding reopens when the value changes.',
          });
        },
      },
    );
  };
  const confirmRemove = () => {
    if (!removing) return;
    remove.mutate(removing.annotationId, {
      onSuccess: () => {
        setRemoving(null);
        notifications.show({
          color: 'blue',
          title: 'Annotation removed',
          message: 'The finding is new again in every review of this production.',
        });
      },
    });
  };

  const demoNote = DEMO ? (
    <Alert color="blue" variant="light" title="Demo replay" role="note">
      The online demo keeps no annotations: it answers as an instance would refuse a change it cannot make.
    </Alert>
  ) : null;

  const modals = (
    <>
      <Modal
        opened={marking !== null}
        onClose={() => setMarking(null)}
        title={marking ? `Annotate ${marking.id}: ${marking.code}` : ''}
      >
        {marking ? (
          <Stack gap="sm">
            <Text size="sm">
              On {subjectOf(marking)}
              {marking.setting ? `, ${marking.setting}` : ''}: {marking.found}
            </Text>
            <Text size="xs" c="dimmed">
              A record in Shutter, never a change to the production. It is bound to this exact value and
              applies to every review of {review.production}, until the value changes, it expires or it is
              removed.
            </Text>
            {demoNote}
            <Radio.Group label="Mark it as" value={status} onChange={(v) => setStatus(v as Status)}>
              <Stack gap={6} mt={4}>
                {(Object.keys(STATUS_NOTES) as Status[]).map((s) => (
                  <Radio key={s} value={s} label={STATUS_LABELS[s]} description={STATUS_NOTES[s]} />
                ))}
              </Stack>
            </Radio.Group>
            <Textarea
              label="Reason"
              description="Recorded with your name"
              value={reason}
              onChange={(e) => setReason(e.currentTarget.value)}
              autosize
              minRows={2}
              required
              data-autofocus
            />
            <TextInput
              label="Expires on (optional)"
              description="YYYY-MM-DD. The annotation lapses at the end of that day, UTC; the finding is new again after it."
              placeholder="YYYY-MM-DD"
              value={expires}
              onChange={(e) => setExpires(e.currentTarget.value)}
              error={problem ?? undefined}
              w={240}
            />
            {annotate.error ? (
              <Text size="sm" c="red" role="alert">
                {describeError(annotate.error)}
              </Text>
            ) : null}
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setMarking(null)}>
                Cancel
              </Button>
              <Button onClick={submit} loading={annotate.isPending} disabled={!reason.trim() || !!problem}>
                Mark as {STATUS_LABELS[status].toLowerCase()}
              </Button>
            </Group>
          </Stack>
        ) : null}
      </Modal>
      <Modal
        opened={removing !== null}
        onClose={() => setRemoving(null)}
        title={removing ? `Remove the annotation of ${removing.id}` : ''}
      >
        {removing ? (
          <Stack gap="sm">
            <Text size="sm">
              The finding {removing.code} on {subjectOf(removing)} is marked{' '}
              {STATUS_LABELS[removing.status].toLowerCase()}. Removed, it is new again in every review of{' '}
              {review.production}; the annotation is kept for the record.
            </Text>
            {demoNote}
            {remove.error ? (
              <Text size="sm" c="red" role="alert">
                {describeError(remove.error)}
              </Text>
            ) : null}
            <Group justify="flex-end">
              <Button variant="default" onClick={() => setRemoving(null)}>
                Cancel
              </Button>
              <Button color="red" onClick={confirmRemove} loading={remove.isPending}>
                Remove the annotation
              </Button>
            </Group>
          </Stack>
        ) : null}
      </Modal>
    </>
  );
  return { mark, unmark, modals };
}
