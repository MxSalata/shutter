import { Alert, Button, Group, List, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { resolveCan } from '@/api/can';
import { newIdempotencyKey } from '@/api/client';
import { useFurtherRelease, useFurtherStop, useMe } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { NOT_IN_TRIAL, toBecomeApprover } from '@/env/copy';
import { describeError, isApiError } from '@/lib/errors';
import { formatZoned } from '@/lib/format';
import { ConfirmModal } from '@/components/ConfirmModal';
import { Section } from './Section';

/** What the person confirms by releasing, said where they decide. */
const CONFIRMS =
  "You're confirming you've read these messages in the source system and this write is still right beside them. It holds only for these rows: a further message voids it. Every other check still runs, and the write still needs its approval.";

/**
 * A write stopped by another visit's movement (FURTHER_MOVEMENT): the rows that stopped it, read afresh, and for an approver
 * the release of this one stop, bound to those rows with a typed reason (CONTRACTS 6.5). The trial has no such run to replay,
 * so it says what the button does and leaves it disabled.
 */
export function FurtherStopPanel({ c }: { c: CaseDetail }) {
  const { data: me } = useMe();
  const stop = useFurtherStop(c.caseId, !TRIAL);
  const release = useFurtherRelease(c.caseId);
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const [key, setKey] = useState('');

  if (TRIAL) {
    return (
      <Section id="further-stop" title="Another visit for this patient">
        <Text size="sm">{CONFIRMS}</Text>
        <Group gap="sm" wrap="wrap">
          <Button variant="light" disabled aria-describedby="further-stop-trial">
            Release this stop…
          </Button>
          <Text size="xs" c="dimmed" id="further-stop-trial">
            {NOT_IN_TRIAL.recording}
          </Text>
        </Group>
      </Section>
    );
  }

  const view = stop.data;
  if (!view) {
    return stop.isError ? (
      <Section id="further-stop" title="Another visit for this patient">
        <Text size="sm" role="alert">
          The messages could not be read: {describeError(stop.error)}
        </Text>
      </Section>
    ) : null;
  }
  const canRelease = resolveCan(me).approve;
  const open = () => {
    setReason('');
    setKey(newIdempotencyKey());
    release.reset();
    setOpened(true);
  };
  const submit = () =>
    release.mutate(
      { digest: view.digest, reason: reason.trim(), idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'gray',
            title: 'Stop released',
            message: 'The case is read afresh. Every other check runs, and the write comes to an approver.',
          });
        },
      },
    );
  const code = isApiError(release.error) ? release.error.code : '';

  return (
    <Section id="further-stop" title="Another visit for this patient">
      <Text size="sm">
        These came in for the same patient on another visit, and Shutter can't say which is right, so nothing
        is sent.
      </Text>
      <List size="sm" spacing={4}>
        {view.rows.map((row) => (
          <List.Item key={row.line}>{row.line}</List.Item>
        ))}
      </List>
      {view.release && !view.release.stands ? (
        <Alert color="yellow">
          {`${view.release.by}'s release of ${formatZoned(view.release.at)} no longer holds: these aren't the rows they read.`}
        </Alert>
      ) : null}
      {!view.releasable ? (
        <Text size="sm">This stop can't be released here. {view.whyNot}</Text>
      ) : canRelease ? (
        <>
          <Text size="sm">{CONFIRMS}</Text>
          <Group gap="sm">
            <Button variant="light" onClick={open}>
              Release this stop…
            </Button>
          </Group>
        </>
      ) : (
        <Text size="sm">An approver can release this stop for these rows: {toBecomeApprover()}.</Text>
      )}
      <ConfirmModal
        opened={opened}
        onClose={() => setOpened(false)}
        title={`Release the stop on ${c.caseId}`}
      >
        <Stack gap="sm">
          <Text size="sm">{CONFIRMS}</Text>
          <Textarea
            label="Why it's safe to send"
            description="Recorded on the case with your name"
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
            data-autofocus
          />
          {release.error ? (
            <Text size="sm" c="red" role="alert">
              {code === 'rows_changed'
                ? 'The messages changed while you read them: close this and read them again.'
                : describeError(release.error)}
            </Text>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button
              onClick={submit}
              loading={release.isPending}
              disabled={!reason.trim() || code === 'rows_changed'}
            >
              Release for these rows
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </Section>
  );
}
