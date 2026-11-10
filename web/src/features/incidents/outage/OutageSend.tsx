import { Button, Checkbox, Group, List, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCopyCheck, IconSend, IconTool } from '@tabler/icons-react';
import { useId, useState } from 'react';
import { Link } from 'react-router';
import { newIdempotencyKey } from '@/api/client';
import { ConfirmModal } from '@/components/ConfirmModal';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { isApiError } from '@/lib/errors';
import { useApproveOutage, useOutageAct } from './hooks';
import { TechDetail } from '@/components/TechDetail';
import {
  approveConsequence,
  asSentence,
  byMessage,
  closureLabel,
  needsReceiverCheck,
  refusalWords,
  resendStatus,
  runRows,
  stoppedBy,
  stoppedWords,
} from './outageWords';
import type { Outage, OutageRow, Resend } from './types';

/*
 * The send on an outage card (CONTRACTS 17.8, docs/design-1.4.0.md 2 to 4): the one approval of an offered set, "already
 * handled by hand" for one offered message at a receiver whose duplicates are unknown, the messages closed with no send
 * of their own, and the ledger's rows with how each ended. Every control shows only where the row lists its act and the
 * person holds the approver role; the card decides that and renders these only then.
 */

const NOTE_MAX = 1000;

/** The approval of an offered set: a dialog with the messages in order, the receiver check where it is needed, and a note. */
export function ApproveResend({ outage: o }: { outage: Outage }) {
  const approve = useApproveOutage(o.id);
  const [opened, setOpened] = useState(false);
  const [note, setNote] = useState('');
  const [checked, setChecked] = useState(false);
  const [key, setKey] = useState('');
  // The server can ask for the check where the page did not read it as needed (the profile changed meanwhile)
  const [asked, setAsked] = useState(false);
  const needsCheck = needsReceiverCheck(o) || asked;
  const checkWhy = useId();
  const n = o.lists.offered.length;
  const open = () => {
    setNote('');
    setChecked(false);
    setAsked(false);
    setKey(newIdempotencyKey());
    approve.reset();
    setOpened(true);
  };
  const submit = () =>
    approve.mutate(
      {
        digest: o.set.digest ?? '',
        note: note.trim(),
        version: o.version,
        ...(needsCheck ? { receiverChecked: checked } : {}),
        idempotencyKey: key,
      },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: `Approved: ${n === 1 ? '1 message' : `${n} messages`} to send`,
            message: 'The engine sends them one at a time, in order; the card shows how each ended.',
          });
        },
        onError: (e) => {
          if (isApiError(e) && e.code === 'receiver_check_needed') setAsked(true);
          // A new key for the next try: the refused one would replay the refusal
          setKey(newIdempotencyKey());
        },
      },
    );
  return (
    <>
      <Group gap="sm" wrap="wrap">
        <Button
          leftSection={<IconSend size={16} aria-hidden />}
          onClick={open}
          className="wrap-button"
          maw="100%"
        >
          Approve the resend…
        </Button>
        <Text size="xs" c="dimmed">
          {n === 1 ? 'One message' : `${n} messages`}, in order. Nothing is sent until you approve.
        </Text>
      </Group>
      <ConfirmModal
        opened={opened}
        onClose={() => (approve.isPending ? undefined : setOpened(false))}
        title="Approve the resend"
        size="lg"
      >
        <Stack gap="sm">
          <Text size="sm" fw={600} data-testid="confirm-consequence">
            {approveConsequence(o)}
          </Text>
          <List type="ordered" size="sm" spacing={2} aria-label="The messages to send, in order">
            {o.lists.offered.map((r) => (
              <List.Item key={r.headerId}>
                Control id {r.controlId || 'not read'} (header {r.headerId})
              </List.Item>
            ))}
          </List>
          {needsCheck ? (
            <Stack gap={4}>
              <Checkbox
                checked={checked}
                onChange={(e) => setChecked(e.currentTarget.checked)}
                label="I checked the receiver for each of these messages"
                aria-describedby={checkWhy}
              />
              <Text size="xs" c="dimmed" id={checkWhy} pl={32}>
                This receiver is not known to refuse a duplicate, so a message already entered there by hand
                could be filed twice. For one entered by hand, close this and choose Already handled by hand
                instead.
              </Text>
            </Stack>
          ) : null}
          <Textarea
            label="What was checked, and with whom"
            description="Recorded with the approval, under your name"
            value={note}
            onChange={(e) => setNote(e.currentTarget.value)}
            maxLength={NOTE_MAX}
            autosize
            minRows={2}
            data-autofocus
          />
          <Text size="xs" c="dimmed">
            The approval stands for 15 minutes before the first send. If the list changes meanwhile, nothing
            is sent.
          </Text>
          {approve.isError ? (
            <StatusNotice tone="blocking" title="Not approved" role="alert">
              <Text size="sm">{refusalWords(approve.error)}</Text>
            </StatusNotice>
          ) : null}
          <Group justify="flex-end" gap="sm">
            <Button variant="default" onClick={() => setOpened(false)} disabled={approve.isPending}>
              Cancel
            </Button>
            <Button
              leftSection={<IconSend size={16} aria-hidden />}
              onClick={submit}
              loading={approve.isPending}
              disabled={!note.trim() || (needsCheck && !checked)}
            >
              Approve and resend
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </>
  );
}

/**
 * "Already handled by hand" for one offered message: a person says it was entered at the receiver by hand, so Shutter
 * sends nothing for it, takes it off the list and closes its cases as handled by hand. Confirmed in a dialog, with a note.
 */
export function HandledByHand({ outage: o, row }: { outage: Outage; row: OutageRow }) {
  const act = useOutageAct(o.id);
  const [opened, setOpened] = useState(false);
  const [note, setNote] = useState('');
  const [key, setKey] = useState('');
  const control = row.controlId || `header ${row.headerId}`;
  const open = () => {
    setNote('');
    setKey(newIdempotencyKey());
    act.reset();
    setOpened(true);
  };
  const submit = () =>
    act.mutate(
      {
        act: 'handled_by_hand',
        headerId: row.headerId,
        note: note.trim(),
        version: o.version,
        idempotencyKey: key,
      },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: `Control id ${control}: handled by hand`,
            message: 'Shutter sends nothing for it; its cases are closed as handled by hand.',
          });
        },
        onError: () => setKey(newIdempotencyKey()),
      },
    );
  return (
    <>
      <Button
        size="compact-xs"
        variant="default"
        leftSection={<IconTool size={14} aria-hidden />}
        onClick={open}
        aria-label={`Already handled by hand: control id ${control}`}
      >
        Already handled by hand…
      </Button>
      <ConfirmModal
        opened={opened}
        onClose={() => (act.isPending ? undefined : setOpened(false))}
        title="Already handled by hand"
      >
        <Stack gap="sm">
          <Text size="sm" fw={600} data-testid="confirm-consequence">
            Shutter will send nothing for control id {control} (header {row.headerId}), take it off the list
            and close its cases as handled by hand.
          </Text>
          <Text size="sm">
            Choose this only once the receiver shows the message was entered there by hand. It cannot be sent
            from this outage afterwards.
          </Text>
          <Textarea
            label="What you checked at the receiver, and with whom"
            description="Recorded on the outage and the message's cases, under your name"
            value={note}
            onChange={(e) => setNote(e.currentTarget.value)}
            maxLength={NOTE_MAX}
            autosize
            minRows={2}
            data-autofocus
          />
          {act.isError ? (
            <StatusNotice tone="blocking" title="Not recorded" role="alert">
              <Text size="sm">
                {refusalWords(act.error).replace('Nothing was sent', 'Nothing was recorded')}
              </Text>
            </StatusNotice>
          ) : null}
          <Group justify="flex-end" gap="sm">
            <Button variant="default" onClick={() => setOpened(false)} disabled={act.isPending}>
              Cancel
            </Button>
            <Button onClick={submit} loading={act.isPending} disabled={!note.trim()}>
              Close it, send nothing
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </>
  );
}

/** The messages of the window closed with no send of their own: already at the receiver, by its answer or by hand. */
export function ClosedList({ rows }: { rows: OutageRow[] }) {
  return (
    <Stack gap={2} data-testid="outage-closed">
      <Text size="sm" fw={600}>
        Closed: already at the receiver ({rows.length})
      </Text>
      <List size="sm" spacing={4}>
        {rows.map((r) => (
          <List.Item key={r.headerId}>
            <Group gap={6} wrap="wrap" component="span">
              <span>
                Control id {r.controlId || 'not read'} (header {r.headerId})
              </span>
              <StatusBadge
                tone="neutral"
                label={closureLabel(r.closure)}
                icon={r.closure === 'handled_by_hand' ? IconTool : IconCopyCheck}
              />
            </Group>
            {r.reason ? (
              <Text size="sm" c="dimmed">
                {r.reason}
              </Text>
            ) : null}
          </List.Item>
        ))}
      </List>
    </Stack>
  );
}

/** One row of the ledger: the message, how it ended, the engine's or the person's words, who and when, and its case. */
function ResendItem({ r }: { r: Resend }) {
  const status = resendStatus(r);
  return (
    <List.Item data-closure={r.closure ?? r.state}>
      <Group gap={6} wrap="wrap" component="span">
        <span>
          Control id {r.controlId || 'not read'} (header {r.headerId}
          {r.newHeaderId ? `, sent as header ${r.newHeaderId}` : ''})
        </span>
        <StatusBadge tone={status.tone} label={status.label} icon={status.icon} />
      </Group>
      {r.words ? <Text size="sm">{asSentence(r.words)}</Text> : null}
      <Group gap={4} wrap="wrap">
        {r.by ? (
          <Text size="xs" c="dimmed">
            {r.runId.startsWith('H') ? 'Recorded by' : 'Approved by'} {r.by}
          </Text>
        ) : null}
        {r.at ? <Timestamp iso={r.at} size="xs" c="dimmed" short /> : null}
        {r.caseId ? (
          <Text size="xs" c="dimmed">
            Case <Link to={`/cases/${encodeURIComponent(r.caseId)}`}>{r.caseId}</Link>
          </Text>
        ) : null}
      </Group>
    </List.Item>
  );
}

/**
 * The ledger's rows by message: each message once, as it stands now (its latest row: a message one run left unsent and a
 * later run sent reads Sent), what Shutter sent and how each ended, and the messages closed by hand; the rows a later run
 * replaced are folded beneath, for the record.
 */
export function ResendList({ resends }: { resends: Resend[] }) {
  const { latest, earlier } = byMessage(resends);
  const sent = latest.filter((r) => !r.runId.startsWith('H'));
  const byHand = latest.filter((r) => r.runId.startsWith('H'));
  return (
    <Stack gap="xs" data-testid="outage-resends">
      {sent.length ? (
        <Stack gap={2}>
          <Text size="sm" fw={600} id="outage-resends-sent">
            Each message sent, in order ({sent.length})
          </Text>
          <List type="ordered" size="sm" spacing={4} aria-labelledby="outage-resends-sent">
            {sent.map((r) => (
              <ResendItem key={`${r.runId}:${r.position}`} r={r} />
            ))}
          </List>
        </Stack>
      ) : null}
      {byHand.length ? (
        <Stack gap={2}>
          <Text size="sm" fw={600}>
            Closed by hand, nothing sent ({byHand.length})
          </Text>
          <List size="sm" spacing={4}>
            {byHand.map((r) => (
              <ResendItem key={`${r.runId}:${r.headerId}`} r={r} />
            ))}
          </List>
        </Stack>
      ) : null}
      {earlier.length ? (
        <TechDetail kind="data" label={`Earlier runs' rows, replaced by a later one (${earlier.length})`}>
          <List size="sm" spacing={4} data-testid="outage-resends-earlier">
            {earlier.map((r) => (
              <ResendItem key={`${r.runId}:${r.position}:${r.headerId}`} r={r} />
            ))}
          </List>
        </TechDetail>
      ) : null}
    </Stack>
  );
}

/**
 * A message whose latest row is a failed or unknown resend: which message, what the engine read, and what happens next.
 * A message a later row settled is not shown here: the card follows each message's latest state.
 */
export function FailedResend({ resends }: { resends: Resend[] | undefined }) {
  const r = stoppedBy(resends);
  if (!r) return null;
  return (
    <StatusNotice
      tone={r.closure === 'failed' ? 'blocking' : 'attention'}
      title={r.closure === 'failed' ? 'A resend failed' : "A resend's result is not known yet"}
    >
      <Text size="sm" data-testid="outage-failed-resend">
        {stoppedWords(r, runRows(resends)[0]?.runId)}
      </Text>
    </StatusNotice>
  );
}
