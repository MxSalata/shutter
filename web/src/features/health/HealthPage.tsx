import { Accordion, Card, Group, Stack, Text, ThemeIcon } from '@mantine/core';
import { IconCheck, IconMinus, IconX } from '@tabler/icons-react';
import { Fragment, type ReactNode } from 'react';
import { useHealth, useLibrary } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { JsonBlock } from '@/components/JsonBlock';
import { Timestamp } from '@/components/Timestamp';
import { StackTable } from '@/components/StackTable';
import { TRIAL } from '@/env/mode';
import { humanize, keyLabel } from '@/lib/format';

/** The report's keys in words; any other key is humanized. */
const LABELS: Record<string, string> = {
  installed_at: 'Installed',
  demo: 'Demo installation',
  adt_in: 'ADT inbound folder',
  interoperability: 'Interoperability enabled in the namespace',
  production_class: 'Production class compiled',
  production_state: 'Production state',
  aihub_runner: 'AI Hub runner compiled',
  ai_hub_present: 'AI Hub installed',
  mock_config: 'API mimic setting',
  recordings: 'Recorded agent runs',
  working_cases: 'Cases still in progress',
  abandon_after_minutes: 'Abandon allowed after (minutes)',
  license: 'Licence',
  api_webapp: 'REST API web application',
  ui_webapp: 'Web app (this page)',
  wards_webapp: 'Downstream system web application',
  webapps_checked: 'Web applications checked from',
};
const label = (k: string) => LABELS[k] ?? keyLabel(k);

/**
 * What a No means in the demo, for the checks the instance the demo was recorded on did not have: said in a neutral
 * tone, since nothing is wrong with the demo.
 */
const DEMO_ABSENT: Record<string, string> = {
  aihub_runner:
    "Not in the demo: the recorded instance had no AI Hub, so the class that runs agents through it was not compiled. The board's runs in the demo are replays of recorded runs.",
  ai_hub_present:
    'Not in the demo: the demo was recorded on an instance without AI Hub. An installation on the AI Hub image has it.',
  purge_task:
    'Not in the demo: the recorded instance had no message purge task. An installation makes one when SHUTTER_MESSAGE_PURGE asks for it.',
};

/** An icon and its word side by side: the icon never carries the meaning alone. */
function Mark({ color, icon, word }: { color: string; icon: ReactNode; word: string }) {
  return (
    <Group gap={6} wrap="nowrap">
      <ThemeIcon size="sm" radius="xl" color={color} variant="light" aria-hidden>
        {icon}
      </ThemeIcon>
      <Text size="sm">{word}</Text>
    </Group>
  );
}

/**
 * A report value: true and false as a mark and a word (a No the demo is expected to show says why, in grey), nothing
 * as "Not reported", a time as a time, an object as its fields in words, numbers and text as they are (a 1 can be a
 * count).
 */
function Value({ k, value }: { k: string; value: unknown }) {
  if (value === true) return <Mark color="green" icon={<IconCheck size={14} />} word="Yes" />;
  if (value === false) {
    const absent = TRIAL ? DEMO_ABSENT[k] : undefined;
    return (
      <Stack gap={2}>
        <Mark color="gray" icon={absent ? <IconMinus size={14} /> : <IconX size={14} />} word="No" />
        {absent ? (
          <Text size="xs" c="dimmed" maw="80ch">
            {absent}
          </Text>
        ) : null}
      </Stack>
    );
  }
  if (value === null || value === undefined || value === '') {
    return <Mark color="yellow" icon={<IconMinus size={14} />} word="Not reported" />;
  }
  if (typeof value === 'string' && k.endsWith('_at') && !Number.isNaN(Date.parse(value))) {
    return <Timestamp iso={value} />;
  }
  if (typeof value === 'object' && !Array.isArray(value)) {
    return (
      <Stack gap={0}>
        {Object.entries(value as Record<string, unknown>).map(([field, v]) => (
          <Text key={field} size="sm">
            {`${humanize(field)}: ${typeof v === 'object' && v !== null ? JSON.stringify(v) : String(v)}`}
          </Text>
        ))}
      </Stack>
    );
  }
  const text = typeof value === 'object' ? JSON.stringify(value) : String(value);
  // Names, paths and codes in the monospace font; a sentence or a phrase in the text font
  return (
    <Text size="sm" className={/\s/.test(text) ? undefined : 'mono-wrap'}>
      {text}
    </Text>
  );
}

/**
 * The board a case convenes by default, apart from the enabled agents the report counts: the library's members on
 * the default board, by role, and the enabled coordinator ("3 specialists and the coordinator").
 */
function DefaultBoard() {
  const library = useLibrary();
  if (!library.data) return null;
  const board = library.data.filter((m) => m.enabled && m.inDefaultBoard);
  const specialists = board.filter((m) => m.role === 'specialist').length;
  // The server convenes any enabled coordinator, whether or not it is marked for the default board
  const coordinator = library.data.some((m) => m.enabled && m.role === 'coordinator');
  const others = board.filter((m) => m.role !== 'specialist' && m.role !== 'coordinator').length;
  const parts = [
    specialists ? `${specialists} specialist${specialists === 1 ? '' : 's'}` : '',
    coordinator ? 'the coordinator' : '',
    others ? `${others} other${others === 1 ? '' : 's'}` : '',
  ].filter(Boolean);
  return (
    <StackTable.Tr>
      <StackTable.Th w={220} style={{ fontWeight: 500 }}>
        <Text size="sm" c="dimmed">
          Default board
        </Text>
      </StackTable.Th>
      <StackTable.Td>
        <Text size="sm">{parts.length ? parts.join(' and ') : 'nobody'}</Text>
        <Text size="xs" c="dimmed">
          From the agent library; the generalist answers only in single investigator mode
        </Text>
      </StackTable.Td>
    </StackTable.Tr>
  );
}

export default function HealthPage() {
  const health = useHealth();
  const report =
    health.data && typeof health.data === 'object' ? (health.data as Record<string, unknown>) : null;
  return (
    <>
      <PageHeader
        tour="health"
        title="Health"
        subtitle="The installation's own readiness report: namespace, production, web applications, downstream system, knowledge and agents."
      />
      <Card padding="md">
        {health.isPending ? <PageSkeleton label="Checking…" /> : null}
        {health.isError ? (
          <ErrorAlert
            error={health.error}
            title="The readiness report could not be read"
            onRetry={() => void health.refetch()}
          />
        ) : null}
        {report ? (
          <Stack gap="sm">
            {TRIAL ? (
              <Text size="sm" maw="80ch">
                The report of the instance the demo was recorded on. A No that carries a note saying
                &ldquo;Not in the demo&rdquo; is a piece that instance did not have: expected, not a fault.
              </Text>
            ) : null}
            <StackTable className="kv-list" withRowBorders={false} verticalSpacing={4}>
              <StackTable.Tbody>
                {Object.entries(report).map(([k, v]) => (
                  <Fragment key={k}>
                    <StackTable.Tr>
                      <StackTable.Th w={220} style={{ fontWeight: 500 }}>
                        <Text size="sm" c="dimmed">
                          {label(k)}
                        </Text>
                      </StackTable.Th>
                      <StackTable.Td>
                        <Value k={k} value={v} />
                        {k === 'mode' ? (
                          <Text size="xs" c="dimmed">
                            Set by the last scenario run or a reset; live failures are investigated in it too
                          </Text>
                        ) : null}
                      </StackTable.Td>
                    </StackTable.Tr>
                    {k === 'board_members' ? <DefaultBoard /> : null}
                  </Fragment>
                ))}
              </StackTable.Tbody>
            </StackTable>
            <Accordion variant="contained" chevronPosition="left">
              <Accordion.Item value="raw">
                <Accordion.Control>
                  <Text size="xs">The report as the API sends it</Text>
                </Accordion.Control>
                <Accordion.Panel>
                  <JsonBlock value={report} label="readiness report" />
                </Accordion.Panel>
              </Accordion.Item>
            </Accordion>
          </Stack>
        ) : null}
      </Card>
    </>
  );
}
