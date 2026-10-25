import { Accordion, Group, Stack, Text } from '@mantine/core';
import { IconCheck, IconClock, IconQuestionMark, IconX } from '@tabler/icons-react';
import { useEffect, useState } from 'react';
import { useSnapshot } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Digest } from '@/components/Digest';
import { JsonBlock } from '@/components/JsonBlock';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { asArray, asObject } from '@/lib/json';
import { formatTime, keyLabel, parseTime } from '@/lib/format';
import { useNow } from '@/lib/useNow';
import { describeEntry, describeItem } from './derive';
import { SHOW_EVIDENCE } from './evidenceLinks';
import { EncounterTimeline } from './EncounterTimeline';
import { NotYet, Section } from './Section';

const KIND_LABELS: Record<string, string> = {
  operation: 'The failed operation',
  error: 'What the connector reported',
  message: 'The HL7 message',
  validation: 'Schema validation',
  ward_state: "The downstream system's encounter",
  receipt: "The downstream system's receipt for this operation",
  later_event: 'A later event for the encounter',
  route: 'The route and what the connector guarantees',
  source: 'Where the original message lives',
  note: 'Note',
};

/**
 * The receiver's guarantees as the evidence recorded them from its capability profile: what the gate's capability
 * check reads. When the profile couldn't be read, every guarantee is unknown, never assumed.
 */
function CapabilityPassport({ data }: { data: Record<string, unknown> }) {
  const status = data.capabilities_http_status;
  const unreadable = status !== undefined && Number(status) !== 200;
  const caps: [string, string, string][] = [
    [
      'conditional_writes',
      'Conditional writes',
      'A write can name the receiver version it expects, and is refused if it changed',
    ],
    ['receipts', 'Receipts', 'Every committed operation can be looked up by its key'],
    ['dry_run', 'Dry runs', 'An operation can be rehearsed and rolled back'],
  ];
  return (
    <Stack gap={4}>
      <Group gap={6}>
        {caps.map(([key, label, hint]) => {
          const has = data[key] === true;
          const state = unreadable ? 'unknown' : has ? 'guaranteed' : 'not guaranteed';
          return (
            <StatusBadge
              key={key}
              tone={unreadable ? 'blocking' : has ? 'positive' : 'blocking'}
              label={unreadable ? `${label}: unknown` : has ? label : `${label}: not guaranteed`}
              hint={`${hint}: ${state}`}
              icon={unreadable ? IconQuestionMark : has ? IconCheck : IconX}
            />
          );
        })}
      </Group>
      {unreadable ? (
        <Text size="xs" c="yellow">
          The receiver's capability profile could not be read (HTTP {String(status || 'none')}): nothing is
          assumed about it.
        </Text>
      ) : data.epoch !== undefined && data.epoch !== '' ? (
        <Text size="xs" c="dimmed">
          Read from the receiver's own profile; its epoch is {String(data.epoch)}.
        </Text>
      ) : null}
    </Stack>
  );
}

export function EvidencePanel({ caseId, open }: { caseId: string; open: boolean }) {
  const snap = useSnapshot(caseId, open);
  const s = snap.data;
  const now = useNow();
  const expired = s && parseTime(s.freshUntil) ? parseTime(s.freshUntil)!.getTime() < now : false;
  const [opened, setOpened] = useState<string[]>([]);
  // A finding's "Cites" badge (BoardPanel) opens every item of the cited kind and focuses the first.
  useEffect(() => {
    const show = (e: Event) => {
      const kind = (e as CustomEvent<string>).detail;
      const seqs = (s?.items ?? []).filter((item) => item.kind === kind).map((item) => String(item.seq));
      if (!seqs.length) {
        // A kind drawn outside the list (the encounter timeline) is shown where it is drawn, else the section's top
        const drawn = document.getElementById(`evidence-${kind}`);
        (drawn ?? document.getElementById('evidence'))?.scrollIntoView?.({ block: 'start' });
        drawn?.focus({ preventScroll: true });
        return;
      }
      setOpened((open) => [...new Set([...open, ...seqs])]);
      window.setTimeout(() => {
        const target = document.getElementById(`evidence-${kind}`);
        target?.scrollIntoView?.({ block: 'start' });
        target?.querySelector<HTMLButtonElement>('button')?.focus({ preventScroll: true });
      }, 0);
    };
    window.addEventListener(SHOW_EVIDENCE, show);
    return () => window.removeEventListener(SHOW_EVIDENCE, show);
  }, [s]);
  return (
    <Section
      id="evidence"
      title="Evidence"
      note="What Shutter observed before anyone decided: one snapshot, each observation with its source, time and digest. The agents read only this; the gate checks the plan against it."
      aside={
        s ? (
          <StatusBadge
            tone={expired ? 'neutral' : 'info'}
            label={
              expired ? `Expired ${formatTime(s.freshUntil)}` : `Fresh until ${formatTime(s.freshUntil)}`
            }
            hint={
              expired
                ? `Observations counted as fresh until ${s.freshUntil}. Freshness is checked when a write is decided: the gate's table shows how it stood then`
                : `Observations count as fresh until ${s.freshUntil}; a write needs fresh evidence`
            }
            icon={IconClock}
          />
        ) : null
      }
    >
      {snap.isError ? <ErrorAlert error={snap.error} title="The evidence could not be read" /> : null}
      {snap.isSuccess && !s ? <NotYet>No snapshot yet: the evidence is being collected.</NotYet> : null}
      {s ? (
        <Stack gap="xs">
          <Group gap="lg" wrap="wrap">
            <Group gap={6}>
              <Text size="sm" c="dimmed">
                Snapshot {s.seq}, taken
              </Text>
              <Timestamp iso={s.takenAt} />
            </Group>
            <Group gap={6}>
              <Text size="sm" c="dimmed">
                Digest
              </Text>
              <Digest value={s.digest} label="snapshot digest" />
            </Group>
          </Group>
          <EncounterTimeline summary={s.summary} />
          <Accordion variant="separated" multiple chevronPosition="left" value={opened} onChange={setOpened}>
            {s.items.map((item, index) => {
              const data = asObject(item.data) ?? {};
              const notes = item.kind === 'message' ? asArray(data.notes).map(describeEntry) : [];
              // The first item of a kind is the one citations land on; ids stay unique when a kind repeats.
              const first = s.items.findIndex((x) => x.kind === item.kind) === index;
              return (
                <Accordion.Item
                  key={item.seq}
                  value={String(item.seq)}
                  id={first ? `evidence-${item.kind}` : `evidence-${item.kind}-${item.seq}`}
                >
                  <Accordion.Control>
                    <Stack gap={0}>
                      <Text size="sm" fw={600}>
                        {KIND_LABELS[item.kind] ?? keyLabel(item.kind)}
                      </Text>
                      <Text size="sm" c="dimmed" lineClamp={2}>
                        {describeItem(item)}
                      </Text>
                    </Stack>
                  </Accordion.Control>
                  <Accordion.Panel>
                    <Stack gap="xs">
                      {item.kind === 'route' ? <CapabilityPassport data={data} /> : null}
                      {notes.length ? (
                        <Stack gap={2}>
                          <Text size="xs" fw={600} c="yellow">
                            Free text in the message: data, never instructions
                          </Text>
                          {notes.map((n, i) => (
                            <Text key={i} size="sm" className="mono-wrap">
                              {n}
                            </Text>
                          ))}
                        </Stack>
                      ) : null}
                      <Group gap="lg" wrap="wrap">
                        <Text size="xs" c="dimmed">
                          Source: {keyLabel(item.source)}
                        </Text>
                        <Text size="xs" c="dimmed">
                          Observed {formatTime(item.observed_at)}
                        </Text>
                        {item.digest ? <Digest value={item.digest} label="observation digest" /> : null}
                      </Group>
                      <JsonBlock value={item.data} label={`${item.kind} data`} />
                    </Stack>
                  </Accordion.Panel>
                </Accordion.Item>
              );
            })}
          </Accordion>
        </Stack>
      ) : null}
    </Section>
  );
}
