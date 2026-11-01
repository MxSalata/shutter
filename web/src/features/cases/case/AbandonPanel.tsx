import { Anchor, Button, Group, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconPlayerStop } from '@tabler/icons-react';
import { useState } from 'react';
import { resolveCan } from '@/api/can';
import { newIdempotencyKey } from '@/api/client';
import { useAbandonCase, useMe } from '@/api/hooks';
import { CLOSED_STATES, type CaseDetail, type CaseEvent } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { NOT_IN_TRIAL } from '@/env/copy';
import { describeError, isApiError } from '@/lib/errors';
import { formatZoned, humanize } from '@/lib/format';
import { useNow } from '@/lib/useNow';
import { ConfirmModal } from './ApprovalPanel';
import { Section } from './Section';

/** How long nothing of a case may move before an approver can abandon it: the server's abandonAfterMinutes default. */
export const ABANDON_AFTER_MINUTES = 15;
const QUIET_MS = ABANDON_AFTER_MINUTES * 60_000;
/**
 * States that wait for a person rather than for work in flight: the open approval task is a deferred message, which
 * the server counts as in flight whatever its age (409 busy), so abandoning is never offered there.
 */
const WAITING_FOR_A_PERSON = ['awaiting_approval', 'grouped'];

/** The newest event's time, any kind: the production's start note counts, so resumed work gets its quiet time. */
function newestAt(events: CaseEvent[]): string {
  return events.reduce((a, e) => (e.at && e.at > a ? e.at : a), '');
}

/** "23 minutes", "3 hours", "2 days". */
function quietFor(ms: number): string {
  const m = Math.floor(ms / 60_000);
  if (m < 120) return `${m} minutes`;
  const h = Math.floor(m / 60);
  return h < 48 ? `${h} hours` : `${Math.floor(h / 24)} days`;
}

/** What a 409 busy answer carries besides its detail (Shutter.Store.Case.InFlight). */
interface Busy {
  newestAt?: string | null;
  deferred?: boolean;
}

/**
 * Gives up a case its workflow left in a working state (a restart in the middle of its work, an answer that never
 * came): for approvers, once nothing of the case has moved for the quiet minutes. The case fails with disposition
 * abandoned and can be reinvestigated; a case that is merely waiting is refused with 409 busy. The trial has no
 * workflow to stop: it shows the control disabled, with its reason, so the capability stays visible.
 */
export function AbandonPanel({ c, events }: { c: CaseDetail; events: CaseEvent[] | null | undefined }) {
  const me = useMe().data;
  const now = useNow();
  const abandon = useAbandonCase(c.caseId);
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const [key, setKey] = useState('');
  const newest = newestAt(events ?? []);
  const quiet = newest ? now - Date.parse(newest) : 0;
  if (
    (!TRIAL && !resolveCan(me).approve) ||
    CLOSED_STATES.includes(c.state) ||
    WAITING_FOR_A_PERSON.includes(c.state) ||
    !newest ||
    quiet < QUIET_MS
  )
    return null;

  const open = () => {
    setReason('');
    setKey(newIdempotencyKey());
    abandon.reset();
    setOpened(true);
  };
  const submit = () =>
    abandon.mutate(
      { reason: reason.trim(), expectedVersion: c.version, idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'gray',
            title: 'Abandoning the case…',
            message: 'The case fails with disposition abandoned; it can be reinvestigated.',
          });
        },
      },
    );

  const error = abandon.error;
  const code = isApiError(error) ? error.code : '';
  const busy = isApiError(error) && error.code === 'busy' ? (error.body as Busy | null) : null;
  const retryMs = busy?.newestAt ? Date.parse(busy.newestAt) + QUIET_MS : 0;
  // A queued message counts as in flight whatever its age, so a time already past would be refused again.
  const retryAt = retryMs > now ? new Date(retryMs).toISOString() : '';
  return (
    <Section
      id="abandon"
      title="Still working"
      note={`The case is ${humanize(c.state).toLowerCase()}. Nothing has moved for ${quietFor(quiet)}.`}
    >
      <Text size="sm">
        Work in flight resumes after a clean restart of the production. If this case's workflow has stopped
        for good, abandoning it fails the case: nothing more is sent, and it can be reinvestigated.
      </Text>
      <Group gap="sm" wrap="wrap">
        <Button
          variant="light"
          color="gray"
          leftSection={<IconPlayerStop size={16} aria-hidden />}
          onClick={open}
          disabled={TRIAL}
          aria-describedby={TRIAL ? 'abandon-reason' : undefined}
        >
          Abandon the case…
        </Button>
        {TRIAL ? (
          <Text size="xs" c="dimmed" id="abandon-reason">
            {NOT_IN_TRIAL.recording}
          </Text>
        ) : null}
      </Group>
      <ConfirmModal opened={opened} onClose={() => setOpened(false)} title={`Abandon ${c.caseId}`}>
        <Stack gap="sm">
          <Textarea
            label="Why give it up"
            description="Recorded on the case with your name"
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
            data-autofocus
          />
          {error ? (
            <Stack gap={4} role="alert">
              <Text size="sm" c="red">
                {code === 'stale_version'
                  ? 'The case changed since this page loaded: close this and look at it again.'
                  : code === 'wrong_state'
                    ? `The case closed meanwhile: ${describeError(error)}`
                    : describeError(error)}
              </Text>
              {busy?.deferred ? (
                <Anchor href="#approval" size="sm" onClick={() => setOpened(false)}>
                  An approval task is open: reject the plan instead
                </Anchor>
              ) : retryAt ? (
                <Text size="sm">Try again after {formatZoned(retryAt)}.</Text>
              ) : null}
            </Stack>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button
              color="red"
              onClick={submit}
              loading={abandon.isPending}
              disabled={!reason.trim() || code === 'stale_version' || code === 'wrong_state'}
            >
              Abandon the case
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </Section>
  );
}
