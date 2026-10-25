import { Accordion, Card, Group, Stack, Table, Text, ThemeIcon } from '@mantine/core';
import { IconCheck, IconMinus, IconX } from '@tabler/icons-react';
import { Fragment } from 'react';
import { useHealth, useLibrary } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { JsonBlock } from '@/components/JsonBlock';
import { keyLabel } from '@/lib/format';

/** A report value: true and false as marks, nothing as "not reported", numbers and text as they are (a 1 can be a count). */
function Value({ value }: { value: unknown }) {
  if (value === true) {
    return (
      <ThemeIcon size="sm" radius="xl" color="green" variant="light" role="img" aria-label="yes">
        <IconCheck size={14} />
      </ThemeIcon>
    );
  }
  if (value === false) {
    return (
      <ThemeIcon size="sm" radius="xl" color="gray" variant="light" role="img" aria-label="no">
        <IconX size={14} />
      </ThemeIcon>
    );
  }
  if (value === null || value === undefined || value === '') {
    return (
      <Group gap={6}>
        <ThemeIcon size="sm" radius="xl" color="yellow" variant="light" role="img" aria-label="not reported">
          <IconMinus size={14} />
        </ThemeIcon>
        <Text size="xs" c="dimmed">
          not reported
        </Text>
      </Group>
    );
  }
  return (
    <Text size="sm" className="mono-wrap">
      {typeof value === 'object' ? JSON.stringify(value) : String(value)}
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
    <Table.Tr>
      <Table.Th w={220} style={{ fontWeight: 500 }}>
        <Text size="sm" c="dimmed">
          Default board
        </Text>
      </Table.Th>
      <Table.Td>
        <Text size="sm">{parts.length ? parts.join(' and ') : 'nobody'}</Text>
        <Text size="xs" c="dimmed">
          From the agent library; the generalist answers only in single investigator mode
        </Text>
      </Table.Td>
    </Table.Tr>
  );
}

export default function HealthPage() {
  const health = useHealth();
  const report =
    health.data && typeof health.data === 'object' ? (health.data as Record<string, unknown>) : null;
  return (
    <>
      <PageHeader
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
            <Table withRowBorders={false} verticalSpacing={4}>
              <Table.Tbody>
                {Object.entries(report).map(([k, v]) => (
                  <Fragment key={k}>
                    <Table.Tr>
                      <Table.Th w={220} style={{ fontWeight: 500 }}>
                        <Text size="sm" c="dimmed">
                          {keyLabel(k)}
                        </Text>
                      </Table.Th>
                      <Table.Td>
                        <Value value={v} />
                        {k === 'mode' ? (
                          <Text size="xs" c="dimmed">
                            Set by the last scenario run or a reset; live failures are investigated in it too
                          </Text>
                        ) : null}
                      </Table.Td>
                    </Table.Tr>
                    {k === 'board_members' ? <DefaultBoard /> : null}
                  </Fragment>
                ))}
              </Table.Tbody>
            </Table>
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
