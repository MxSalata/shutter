import { Badge, Group, Stack, Text, Title, VisuallyHidden } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconBooks } from '@tabler/icons-react';
import { useState } from 'react';
import { DEMO_READ_ONLY, readOnlyDemo } from '@/api/can';
import { useCan, useLibrary, useMe, usePatchMember } from '@/api/hooks';
import type { LibraryMember } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { EmptyState } from '@/components/EmptyState';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { TRIAL } from '@/env/mode';
import { describeError } from '@/lib/errors';
import { BoardFlow } from './BoardFlow';
import { groupMembers, libraryLead, onDefaultBoard } from './board';
import { MemberLibraryCard, type LibraryField } from './MemberLibraryCard';
import { toBecomeApprover } from '@/env/copy';

export default function LibraryPage() {
  const me = useMe().data;
  const library = useLibrary();
  const patch = usePatchMember();
  const can = useCan();
  // Which agents sit on the board is a change of the site, as the site profile is (CONTRACTS 5, Shutter_Configure)
  const canEdit = can.configure;
  // The public demo's role reads the library: the switches are not offered, and a note says why
  const reading = readOnlyDemo(can);
  // In the trial a change lasts until the page is reloaded; the card says so once it has been made
  const [changed, setChanged] = useState<ReadonlySet<string>>(new Set());
  const [announcement, setAnnouncement] = useState('');
  const change = (m: LibraryMember, field: LibraryField, value: boolean) =>
    patch.mutate(
      { code: m.code, change: { [field]: value } },
      {
        onSuccess: () => {
          if (!TRIAL) return;
          setChanged((was) => new Set(was).add(m.code));
          setAnnouncement(`${m.name} changed in the trial only.`);
        },
        onError: (e) =>
          notifications.show({ color: 'red', title: `${m.name} was not changed`, message: describeError(e) }),
      },
    );

  const members = library.data;
  const board = groupMembers(members ?? []);
  const count = onDefaultBoard(board);
  // The first member shown explains the word "Knows" once for the page
  const knowsFirst = [...board.specialists, ...board.coordinators, ...board.others][0]?.code;
  const card = (m: LibraryMember) => (
    <MemberLibraryCard
      key={m.code}
      m={m}
      canEdit={canEdit}
      reading={reading}
      busy={patch.isPending}
      knowsTerm={m.code === knowsFirst}
      changedInTrial={changed.has(m.code)}
      onChange={change}
    />
  );

  return (
    <>
      <PageHeader
        tour="library"
        icon={IconBooks}
        hue="violet"
        title="Agent library"
        lead={libraryLead(members ? board.specialists.length : 3)}
        detailsKind="data"
        details={
          <>
            Each member is an IRIS AI Hub agent (<CodeChip>%AI.Agent</CodeChip>), a business operation in the
            production; its terminal tool (<CodeChip>SubmitFindings</CodeChip>,{' '}
            <CodeChip>SubmitPlan</CodeChip>) is its decision. What an agent is (its class, its production
            item, its tools) is code; which agents sit on the board is a setting.
          </>
        }
      />
      {library.isPending ? <PageSkeleton label="Loading the library…" /> : null}
      {library.isError ? (
        <ErrorAlert
          error={library.error}
          title="The library could not be read"
          onRetry={() => void library.refetch()}
        />
      ) : null}
      {members && members.length === 0 ? (
        <EmptyState icon={IconBooks} hue="violet">
          The library has no agents yet.
        </EmptyState>
      ) : null}
      {members && members.length > 0 ? (
        <Stack gap="lg">
          {me && !canEdit ? (
            <Text size="sm" c="dimmed" data-testid={reading ? 'demo-read-only' : undefined}>
              {reading
                ? `${DEMO_READ_ONLY}.`
                : `Changing which agents sit on the board needs the approver role: ${toBecomeApprover()}.`}
            </Text>
          ) : null}
          <Stack component="section" gap="md" aria-labelledby="library-board-title">
            <Group justify="space-between" align="center" gap="sm">
              <Title order={2} id="library-board-title">
                The board
              </Title>
              <Badge color="gray" variant="outline" size="md" style={{ textTransform: 'none' }}>
                On the default board: {count.on} of {count.of}
              </Badge>
            </Group>
            <BoardFlow
              specialists={board.specialists.map(card)}
              coordinators={board.coordinators.map(card)}
            />
          </Stack>
          {board.others.length > 0 ? (
            <Stack component="section" gap="md" aria-labelledby="library-others-title">
              <Title order={2} id="library-others-title">
                Not on the board
              </Title>
              <Stack gap="md">{board.others.map(card)}</Stack>
            </Stack>
          ) : null}
          <ApiSource endpoint="GET /api/shutter/library" data={members} />
          {/* Told to a screen reader when a switch is saved in the trial; the card shows it in words too. Not a
              `status` region: a page has none once its data has arrived. */}
          <VisuallyHidden aria-live="polite" aria-atomic="true">
            {announcement}
          </VisuallyHidden>
        </Stack>
      ) : null}
    </>
  );
}
