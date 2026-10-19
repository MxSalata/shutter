import { Accordion, Card, Group, Stack, Table, Text, ThemeIcon } from '@mantine/core';
import { IconCheck, IconMinus, IconX } from '@tabler/icons-react';
import { useHealth } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { JsonBlock } from '@/components/JsonBlock';
import { keyLabel } from '@/lib/format';

/** A report value: true and false as marks, nothing as "not reported", numbers and text as they are (a 1 can be a count). */
function Value({ value }: { value: unknown }) {
  if (value === true) {
    return (
      <ThemeIcon size="sm" radius="xl" color="teal" variant="light" role="img" aria-label="yes">
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
        <ThemeIcon size="sm" radius="xl" color="orange" variant="light" role="img" aria-label="not reported">
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
                  <Table.Tr key={k}>
                    <Table.Th w={220} style={{ fontWeight: 500 }}>
                      <Text size="sm" c="dimmed">
                        {keyLabel(k)}
                      </Text>
                    </Table.Th>
                    <Table.Td>
                      <Value value={v} />
                    </Table.Td>
                  </Table.Tr>
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
