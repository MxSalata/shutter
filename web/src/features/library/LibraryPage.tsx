import { Badge, Card, Group, Stack, Switch, Table, Text, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useLibrary, useMe, usePatchMember } from '@/api/hooks';
import type { LibraryMember } from '@/api/types';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { describeError } from '@/lib/errors';
import { humanize } from '@/lib/format';

const ROLE_COLOURS: Record<string, string> = {
  specialist: 'indigo',
  coordinator: 'grape',
  generalist: 'cyan',
};

export default function LibraryPage() {
  const me = useMe().data;
  const library = useLibrary();
  const patch = usePatchMember();
  // Which agents sit on the board is an approver's change, as the site profile is (CONTRACTS 5)
  const canEdit = !!me?.approver;
  const change = (m: LibraryMember, field: 'enabled' | 'inDefaultBoard', value: boolean) =>
    patch.mutate(
      { code: m.code, change: { [field]: value } },
      {
        onError: (e) =>
          notifications.show({ color: 'red', title: `${m.name} was not changed`, message: describeError(e) }),
      },
    );
  return (
    <>
      <PageHeader
        title="Agent library"
        subtitle="The agents a board is made from. Each specialist reviews the evidence from one perspective with its own knowledge collection; the coordinator turns their findings into one plan. What an agent is (its class, its production item, its tools) is code; which agents sit on the board is a setting."
      />
      <Card padding="md">
        {library.isPending ? <PageSkeleton label="Loading the library…" /> : null}
        {library.isError ? (
          <ErrorAlert
            error={library.error}
            title="The library could not be read"
            onRetry={() => void library.refetch()}
          />
        ) : null}
        {library.data && me && !canEdit ? (
          <Text size="sm" c="dimmed" mb="sm">
            Changing which agents sit on the board needs the approver role: sign in as approver.
          </Text>
        ) : null}
        {library.data ? (
          <Table.ScrollContainer minWidth={820}>
            <Table>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th>Agent</Table.Th>
                  <Table.Th>Role</Table.Th>
                  <Table.Th>Knowledge</Table.Th>
                  <Table.Th>Production item</Table.Th>
                  <Table.Th>Enabled</Table.Th>
                  <Table.Th>On the default board</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                {library.data.map((m) => (
                  <Table.Tr key={m.code}>
                    <Table.Td maw={380}>
                      <Stack gap={2}>
                        <Text size="sm" fw={600}>
                          {m.name}
                        </Text>
                        <Text size="xs" c="dimmed">
                          {m.perspective || m.description}
                        </Text>
                      </Stack>
                    </Table.Td>
                    <Table.Td>
                      <Badge color={ROLE_COLOURS[m.role] ?? 'gray'} style={{ textTransform: 'none' }}>
                        {humanize(m.role)}
                      </Badge>
                    </Table.Td>
                    <Table.Td>
                      <Text size="sm">{m.knowledgeCollection || 'none'}</Text>
                    </Table.Td>
                    <Table.Td>
                      <Text size="xs" className="mono-wrap">
                        {m.configItem}
                      </Text>
                      <Text size="xs" c="dimmed">
                        {m.agentClass} · v{m.configVersion}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Tooltip label="Needs the approver role" disabled={canEdit}>
                        <Group>
                          <Switch
                            checked={m.enabled}
                            disabled={!canEdit || patch.isPending}
                            onChange={(e) => change(m, 'enabled', e.currentTarget.checked)}
                            aria-label={`${m.name} enabled`}
                          />
                        </Group>
                      </Tooltip>
                    </Table.Td>
                    <Table.Td>
                      {m.role === 'specialist' ? (
                        <Tooltip label="Needs the approver role" disabled={canEdit}>
                          <Group>
                            <Switch
                              checked={m.inDefaultBoard}
                              disabled={!canEdit || !m.enabled || patch.isPending}
                              onChange={(e) => change(m, 'inDefaultBoard', e.currentTarget.checked)}
                              aria-label={`${m.name} on the default board`}
                            />
                          </Group>
                        </Tooltip>
                      ) : (
                        <Text size="xs" c="dimmed">
                          {m.role === 'coordinator' ? 'Always, when enabled' : 'Single-investigator mode'}
                        </Text>
                      )}
                    </Table.Td>
                  </Table.Tr>
                ))}
              </Table.Tbody>
            </Table>
          </Table.ScrollContainer>
        ) : null}
      </Card>
    </>
  );
}
