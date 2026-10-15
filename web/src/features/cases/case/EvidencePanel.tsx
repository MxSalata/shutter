import { Accordion, Badge, Group, Stack, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconQuestionMark, IconX } from '@tabler/icons-react';
import { useSnapshot } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Digest } from '@/components/Digest';
import { JsonBlock } from '@/components/JsonBlock';
import { Timestamp } from '@/components/Timestamp';
import { asArray, asObject } from '@/lib/json';
import { formatTime, humanize, parseTime } from '@/lib/format';
import { useNow } from '@/lib/useNow';
import { describeItem } from './derive';
import { NotYet, Section } from './Section';

const KIND_LABELS: Record<string, string> = {
  operation: 'The failed operation',
  error: 'What the connector reported',
  message: 'The HL7 message',
  validation: 'Schema validation',
  ward_state: "The ward's encounter",
  receipt: "The ward's receipt for this operation",
  later_event: 'A later event for the encounter',
  route: 'The route and what the connector guarantees',
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
          const colour = unreadable ? 'orange' : has ? 'teal' : 'red';
          const state = unreadable ? 'unknown' : has ? 'guaranteed' : 'not guaranteed';
          return (
            <Tooltip key={key} label={`${hint}: ${state}`} multiline maw={300}>
              <Badge
                color={colour}
                variant="light"
                leftSection={
                  unreadable ? (
                    <IconQuestionMark size={12} />
                  ) : has ? (
                    <IconCheck size={12} />
                  ) : (
                    <IconX size={12} />
                  )
                }
                style={{ textTransform: 'none' }}
                tabIndex={0}
              >
                {label}
              </Badge>
            </Tooltip>
          );
        })}
      </Group>
      {unreadable ? (
        <Text size="xs" c="orange">
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
  return (
    <Section
      id="evidence"
      title="Evidence"
      note="What Interlock observed before anyone decided: one snapshot, each observation with its source, time and digest. The agents read only this; the gate checks the plan against it."
      aside={
        s ? (
          <Tooltip label={`Observations count as fresh until ${s.freshUntil}; a write needs fresh evidence`}>
            <Badge
              color={expired ? 'gray' : 'teal'}
              variant="light"
              tabIndex={0}
              style={{ textTransform: 'none' }}
            >
              {expired ? `Expired ${formatTime(s.freshUntil)}` : `Fresh until ${formatTime(s.freshUntil)}`}
            </Badge>
          </Tooltip>
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
          <Accordion variant="separated" multiple chevronPosition="left">
            {s.items.map((item) => {
              const data = asObject(item.data) ?? {};
              const notes = item.kind === 'message' ? asArray<string>(data.notes) : [];
              return (
                <Accordion.Item key={item.seq} value={String(item.seq)} id={`evidence-${item.kind}`}>
                  <Accordion.Control>
                    <Stack gap={0}>
                      <Text size="sm" fw={600}>
                        {KIND_LABELS[item.kind] ?? humanize(item.kind)}
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
                          <Text size="xs" fw={600} c="orange">
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
                          Source: {humanize(item.source)}
                        </Text>
                        <Text size="xs" c="dimmed">
                          Observed {formatTime(item.observedAt)}
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
