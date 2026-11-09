import { Button, Card, Group, List, Stack, Text, TextInput, Textarea, Title } from '@mantine/core';
import { useState } from 'react';
import { Link } from 'react-router';
import { useCan } from '@/api/hooks';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import type { Tone } from '@/lib/tone';
import { useNow } from '@/lib/useNow';
import { useOutageAct, useOutages } from './hooks';
import type { Outage, OutageReading, OutageRow } from './types';

/** A reading older than this, or one that reads unknown, is stale and said loudly. */
const STALE_MS = 60_000;

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
  const shown = data.items.filter((o) => o.state !== 'closed' || o.openCases.length > 0);
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
        label={reading.reading.replace(/_/g, ' ')}
      />
      <Text size="sm">
        {reading.receiver}
        {where ? ` (${where})` : ''}: {ago === null ? 'never checked' : `checked ${ago} s ago`}
        {stale ? '. The watcher has not answered lately: what is shown may be out of date.' : ''}
      </Text>
    </Group>
  );
}

/** One outage: its state, the row's words, alerts, the lists or why there are none, open cases and the acts it lists. */
export function OutageCard({ outage: o }: { outage: Outage }) {
  const can = useCan();
  const closed = o.state === 'closed';
  const computed = o.set.status === 'computed';
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
        {o.words.first ? <Text size="sm">{o.words.first}</Text> : null}
        {o.words.do ? <Text size="sm">{o.words.do}</Text> : null}
        {o.words.call ? <Text size="sm">{o.words.call}</Text> : null}
        {o.words.critical ? (
          <StatusNotice tone="attention" title="Critical results">
            <Text size="sm">{o.words.critical}</Text>
          </StatusNotice>
        ) : null}
        {closed && o.outcome ? <Text size="sm">{o.outcome}</Text> : null}
        {o.alerts.length ? (
          <Stack gap={2}>
            <Text size="sm" fw={600}>
              The engine&apos;s alerts for this item
            </Text>
            <List size="sm" spacing={2}>
              {o.alerts.map((a, i) => (
                <List.Item key={i}>
                  {a.at} {a.kind}: {a.text}
                </List.Item>
              ))}
            </List>
          </Stack>
        ) : null}
        {!closed ? (
          computed ? (
            <Stack gap="xs" data-testid="outage-lists">
              {LISTS.map(({ key, title }) =>
                o.lists[key].length ? <RowList key={key} title={title} rows={o.lists[key]} /> : null,
              )}
            </Stack>
          ) : (
            <Text size="sm" c="dimmed" data-testid="outage-no-lists">
              No list of messages: {o.set.reason || 'the set is not computed yet'}.
            </Text>
          )
        ) : null}
        {o.openCases.length ? (
          <Stack gap={2} data-testid="outage-open-cases">
            <Text size="sm" fw={600}>
              Delivery exceptions still needing review
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
        {can.approve && o.acts.length ? <Acts outage={o} /> : null}
      </Stack>
    </Card>
  );
}

function RowList({ title, rows }: { title: string; rows: OutageRow[] }) {
  return (
    <Stack gap={2}>
      <Text size="sm" fw={600}>
        {title} ({rows.length})
      </Text>
      <List size="sm" spacing={2}>
        {rows.map((r) => (
          <List.Item key={r.headerId}>
            Control id {r.controlId || 'not read'} (header {r.headerId}, {r.status})
            {r.reason ? `: ${r.reason}` : ''}
          </List.Item>
        ))}
      </List>
    </Stack>
  );
}

/** Only the acts the row lists: pause with a time, read again, close with a reason. */
function Acts({ outage: o }: { outage: Outage }) {
  const act = useOutageAct(o.id);
  const [until, setUntil] = useState('');
  const [reason, setReason] = useState('');
  const send = (body: { act: string; until?: string; reason?: string }) =>
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
