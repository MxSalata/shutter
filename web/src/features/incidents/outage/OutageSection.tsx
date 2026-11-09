import { Button, Card, Group, List, Stack, Text, TextInput, Textarea, Title } from '@mantine/core';
import { useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { useCan, useRecoveryControl } from '@/api/hooks';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import type { Tone } from '@/lib/tone';
import { useNow } from '@/lib/useNow';
import { Timestamp } from '@/components/Timestamp';
import { useOutageAct, useOutages } from './hooks';
import { ApproveResend, ClosedList, FailedResend, HandledByHand, ResendList } from './OutageSend';
import {
  approvalHeld,
  approvedLine,
  canApprove,
  closedRowsToShow,
  offeredRowsToShow,
  readingLabel,
  sendingLine,
  tallyLine,
} from './outageWords';
import type { Outage, OutageReading, OutageRow } from './types';

/** A reading older than this, or one that reads unknown, is stale and said loudly. */
const STALE_MS = 60_000;

/** How long a closed outage whose messages Shutter resent stays on the page, so the approver sees how the run ended. */
const RECENT_MS = 24 * 60 * 60_000;

/** The label the design gives the list of messages that never reached the receiver. */
export const OFFERED_LABEL = 'Connection-failure evidence found: review before any resend';

const LISTS: { key: keyof Outage['lists']; title: string }[] = [
  { key: 'offered', title: OFFERED_LABEL },
  { key: 'queued', title: 'Still with the engine: wait' },
  { key: 'reached', title: 'Reached the receiver: check its screen' },
  { key: 'refused', title: 'Not listed, with the reason' },
];

const STATE_TONE: Record<string, Tone> = {
  open: 'blocking',
  draining: 'info',
  closing: 'info',
  offered: 'attention',
  sending: 'info',
  needs_person: 'attention',
  paused: 'neutral',
  closed: 'neutral',
};

/**
 * The receiver outages above the incidents (CONTRACTS 17): one line per watched receiver, and a card per outage with the
 * row's own words, the engine's alerts, the four lists or why there are none, and only the acts the row lists. Nothing
 * when the server has no outage routes (the recorded trial answers 501).
 */
export function OutageSection() {
  const outages = useOutages();
  const now = useNow(5_000);
  const data = outages.data;
  if (!data || (data.items.length === 0 && data.receivers.length === 0)) return null;
  const shown = data.items.filter((o) => o.state !== 'closed' || o.openCases.length > 0 || recentRun(o, now));
  return (
    <Stack gap="sm" mb="md" data-testid="outages">
      <Title order={2} fz="lg">
        Receiver outages
      </Title>
      {data.receivers.length ? (
        <Stack gap={4} data-testid="readings">
          {data.receivers.map((r) => (
            <ReadingLine key={r.receiver} reading={r} now={now} />
          ))}
        </Stack>
      ) : null}
      {shown.map((o) => (
        <OutageCard key={o.id} outage={o} />
      ))}
    </Stack>
  );
}

/** A closed outage with a ledger, closed within the last day. */
function recentRun(o: Outage, now: number): boolean {
  if (!o.resends?.length) return false;
  const at = o.closedAt ? Date.parse(o.closedAt) : NaN;
  return Number.isFinite(at) && now - at < RECENT_MS;
}

/** The always-on line for one watched receiver, loud when its watcher has not written for a minute. */
export function ReadingLine({ reading, now }: { reading: OutageReading; now: number }) {
  const checked = reading.checkedAt ? Date.parse(reading.checkedAt) : NaN;
  const ago = Number.isFinite(checked) ? Math.max(0, Math.round((now - checked) / 1000)) : null;
  const stale = ago === null || ago * 1000 > STALE_MS || reading.reading === 'unknown';
  const where = [reading.item, reading.namespace].filter(Boolean).join(' in ');
  return (
    <Group gap="xs" wrap="wrap" data-stale={stale ? 'true' : 'false'}>
      <StatusBadge
        tone={stale ? 'attention' : reading.reading === 'healthy' ? 'positive' : 'blocking'}
        label={readingLabel(reading.reading)}
      />
      <Text size="sm">
        {reading.receiver}
        {where ? ` (${where})` : ''}: {ago === null ? 'never checked' : `checked ${ago} s ago`}
        {stale ? '. The watcher has not answered lately: what is shown may be out of date.' : ''}
      </Text>
    </Group>
  );
}

/**
 * One outage: its state, the row's words, a failed resend first, alerts, the lists or why there are none (with "already
 * handled by hand" on an offered message that lists it), the approval, the run's progress and the ledger, open cases and
 * the acts it lists. Every control needs the approver role and the row's own act.
 */
export function OutageCard({ outage: o }: { outage: Outage }) {
  const can = useCan();
  const held = approvalHeld(useRecoveryControl().data);
  const closed = o.state === 'closed';
  const computed = o.set.status === 'computed';
  const resends = o.resends ?? [];
  const sentRun = resends.some((r) => !r.runId.startsWith('H'));
  const progress = sendingLine(o);
  const approved = approvedLine(o);
  const tally = tallyLine(resends);
  // A message the ledger shows (sent, already held, handled by hand, not sent) is listed there alone: the set's own lists
  // were read before the run and say nothing of it since
  const closedRows = closedRowsToShow(o);
  const offeredRows = offeredRowsToShow(o);
  const offeredActs = (r: OutageRow) =>
    can.approve && o.state === 'offered' && r.acts?.includes('handled_by_hand') ? (
      <HandledByHand outage={o} row={r} />
    ) : null;
  return (
    <Card padding="md" withBorder component="section" aria-label={`Outage ${o.id}, ${o.receiver}`}>
      <Stack gap="sm">
        <Group gap="xs" wrap="wrap" justify="space-between">
          <Title order={3} fz="md">
            {o.receiver}
            {o.item ? ` (${o.item}${o.namespace ? ` in ${o.namespace}` : ''})` : ''}
          </Title>
          <StatusBadge tone={STATE_TONE[o.state] ?? 'neutral'} label={o.state.replace(/_/g, ' ')} />
        </Group>
        <FailedResend resends={resends} />
        {o.words.first ? <Text size="sm">{o.words.first}</Text> : null}
        {o.words.do ? <Text size="sm">{o.words.do}</Text> : null}
        {o.words.call ? <Text size="sm">{o.words.call}</Text> : null}
        {o.words.critical ? (
          <StatusNotice tone="attention" title="Critical results">
            <Text size="sm">{o.words.critical}</Text>
          </StatusNotice>
        ) : null}
        {/* Once a run went, the ledger's tally says how the outage ended; the close's own words can predate the send */}
        {closed && sentRun && tally ? (
          <Text size="sm" data-testid="outage-tally">
            {tally}
          </Text>
        ) : closed && o.outcome ? (
          <Text size="sm">{o.outcome}</Text>
        ) : null}
        {/* The engine's own alert lines are its raw words (segments and all): folded, so a card stays one card tall */}
        {o.alerts.length ? (
          <TechDetail kind="data" label={`The engine's alerts for this item (${o.alerts.length})`}>
            <List size="sm" spacing={2} className="mono-wrap" data-testid="outage-alerts">
              {o.alerts.map((a, i) => (
                <List.Item key={i}>
                  {a.at} {a.kind}: {a.text}
                </List.Item>
              ))}
            </List>
          </TechDetail>
        ) : null}
        {!closed ? (
          computed ? (
            <Stack gap="xs" data-testid="outage-lists">
              {LISTS.map(({ key, title }) => {
                const rows = key === 'offered' ? offeredRows : (o.lists[key] ?? []);
                return rows.length ? (
                  <RowList
                    key={key}
                    title={title}
                    rows={rows}
                    actions={key === 'offered' ? offeredActs : undefined}
                  />
                ) : null;
              })}
              {closedRows.length ? <ClosedList rows={closedRows} /> : null}
            </Stack>
          ) : (
            <Stack gap="xs">
              <Text size="sm" c="dimmed" data-testid="outage-no-lists">
                No list of messages: {o.set.reason || 'the set is not computed yet'}.
              </Text>
              {closedRows.length ? <ClosedList rows={closedRows} /> : null}
            </Stack>
          )
        ) : null}
        {can.approve && canApprove(o) ? (
          held ? (
            <StatusNotice tone="attention" title="The resend can't be approved now">
              <Text size="sm" data-testid="outage-approval-held">
                {held}
              </Text>
            </StatusNotice>
          ) : (
            <ApproveResend outage={o} />
          )
        ) : null}
        {progress || (approved && !closed) ? (
          <Stack gap={2} role="status" data-testid="outage-sending">
            {progress ? (
              <Text size="sm" fw={600}>
                {progress}
              </Text>
            ) : null}
            {approved && !closed ? (
              <Group gap={4} wrap="wrap">
                <Text size="xs" c="dimmed">
                  {approved}
                </Text>
                {o.approval?.givenAt ? (
                  <Timestamp iso={o.approval.givenAt} size="xs" c="dimmed" short />
                ) : null}
              </Group>
            ) : null}
            {approved && !closed && o.approval?.note ? (
              <Text size="xs" c="dimmed">
                Their note: {o.approval.note}
              </Text>
            ) : null}
          </Stack>
        ) : null}
        {!closed && tally && resends.length ? (
          <Text size="sm" data-testid="outage-tally">
            {tally}
          </Text>
        ) : null}
        {resends.length ? <ResendList resends={resends} /> : null}
        {o.openCases.length ? (
          <Stack gap={2} data-testid="outage-open-cases">
            <Text size="sm" fw={600}>
              Cases still needing a person ({o.openCases.length})
            </Text>
            <List size="sm" spacing={2}>
              {o.openCases.map((c) => (
                <List.Item key={c.caseId}>
                  <Link to={`/cases/${encodeURIComponent(c.caseId)}`}>{c.caseId}</Link>: {c.reason} (owner:{' '}
                  {c.owner})
                </List.Item>
              ))}
            </List>
          </Stack>
        ) : null}
        {/* Nothing while a run is sending: a pause or a close would not stop the send */}
        {can.approve && o.state !== 'sending' && o.acts.some((a) => a !== 'handled_by_hand') ? (
          <Acts outage={o} />
        ) : null}
      </Stack>
    </Card>
  );
}

function RowList({
  title,
  rows,
  actions,
}: {
  title: string;
  rows: OutageRow[];
  /** A control for one row, where the row lists an act (Already handled by hand on an offered message). */
  actions?: (r: OutageRow) => ReactNode;
}) {
  return (
    <Stack gap={2}>
      <Text size="sm" fw={600}>
        {title} ({rows.length})
      </Text>
      <List size="sm" spacing={4}>
        {rows.map((r) => {
          const control = actions?.(r);
          return (
            <List.Item key={r.headerId}>
              Control id {r.controlId || 'not read'} (header {r.headerId}, {r.status})
              {r.reason ? `: ${r.reason}` : ''}
              {control ? <Group mt={4}>{control}</Group> : null}
            </List.Item>
          );
        })}
      </List>
    </Stack>
  );
}

/** Only the acts the row lists: pause with a time, read again, close with a reason. */
function Acts({ outage: o }: { outage: Outage }) {
  const act = useOutageAct(o.id);
  const [until, setUntil] = useState('');
  const [reason, setReason] = useState('');
  const send = (body: { act: 'pause' | 'read_again' | 'close'; until?: string; reason?: string }) =>
    act.mutate({ ...body, version: o.version });
  return (
    <Stack gap="xs" data-testid="outage-acts">
      {o.acts.includes('read_again') ? (
        <Group>
          <Button
            size="xs"
            variant="default"
            loading={act.isPending}
            onClick={() => send({ act: 'read_again' })}
          >
            Read again
          </Button>
        </Group>
      ) : null}
      {o.acts.includes('pause') ? (
        <Group gap="xs" align="flex-end" wrap="wrap">
          <TextInput
            size="xs"
            label="Down on purpose until (UTC)"
            placeholder="2026-11-09T06:00:00Z"
            value={until}
            onChange={(e) => setUntil(e.currentTarget.value)}
          />
          <Button
            size="xs"
            variant="default"
            disabled={!until.trim()}
            onClick={() => send({ act: 'pause', until: until.trim() })}
          >
            Pause
          </Button>
        </Group>
      ) : null}
      {o.acts.includes('close') ? (
        <Group gap="xs" align="flex-end" wrap="wrap">
          <Textarea
            size="xs"
            label="Why close it"
            autosize
            minRows={1}
            maxLength={1000}
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
          />
          <Button
            size="xs"
            variant="default"
            disabled={!reason.trim()}
            onClick={() => send({ act: 'close', reason: reason.trim() })}
          >
            Close
          </Button>
        </Group>
      ) : null}
      {act.isError ? (
        <Text size="sm" c="red" role="alert">
          The act was not taken: {(act.error as { message?: string }).message ?? 'the server refused it'}
        </Text>
      ) : null}
    </Stack>
  );
}
