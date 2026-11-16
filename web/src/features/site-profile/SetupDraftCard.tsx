import { Button, Group, Table, Text } from '@mantine/core';
import { HeroBand } from '@/components/HeroBand';
import { LockedNote } from '@/components/LockedSave';
import { StatusNotice } from '@/components/StatusBadge';
import { SETUP_DRAFT_TITLE_ID, type DraftRow } from './setup/draftRows';

/**
 * A draft handed over by Set up the site, shown above the form once its review has been closed: what it changes, and
 * the ways on. Saving goes through the page's own review and save, approvers only. When the stored profile moved while
 * the draft was being made, nothing was pre-filled, and the band says so.
 */
export function SetupDraftCard({
  rows,
  version,
  stale,
  locked = null,
  onReview,
  onDiscard,
  onBack,
}: {
  rows: DraftRow[];
  /** The version in force. */
  version: number;
  /** The version the draft was made against, when it is no longer the one in force. */
  stale: number | null;
  locked?: string | null;
  onReview: () => void;
  onDiscard: () => void;
  onBack: () => void;
}) {
  return (
    <HeroBand
      tone="attention"
      id="site-setup-draft"
      statementAs="h2"
      statement="A draft from Set up the site"
      statementProps={{ id: SETUP_DRAFT_TITLE_ID, tabIndex: -1 }}
    >
      {stale === null ? (
        <>
          <Text size="md">
            The form below holds this draft. Nothing is saved until an approver reviews and saves it.
          </Text>
          <Table withTableBorder variant="vertical" layout="fixed" captionSide="top">
            <Table.Caption>The changes in this draft</Table.Caption>
            <Table.Thead>
              <Table.Tr>
                <Table.Th scope="col">Setting</Table.Th>
                <Table.Th scope="col">Now, version {version}</Table.Th>
                <Table.Th scope="col">In this draft</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((row, i) => (
                <Table.Tr key={i}>
                  <Table.Th scope="row" fw={400} colSpan={row.now || row.draft ? 1 : 3}>
                    {row.setting}
                  </Table.Th>
                  {row.now || row.draft ? (
                    <>
                      <Table.Td>{row.now}</Table.Td>
                      <Table.Td fw={700}>{row.draft}</Table.Td>
                    </>
                  ) : null}
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </>
      ) : (
        <StatusNotice tone="attention" title="Not pre-filled">
          The draft was made from version {stale}, and version {version} is in force now, so nothing was
          pre-filled. Go back to Set up the site and discard the draft to start from the answers in force.
        </StatusNotice>
      )}
      <Group gap="sm">
        {stale === null ? <Button onClick={onReview}>Review and save…</Button> : null}
        <Button variant="default" onClick={onDiscard}>
          {stale === null ? 'Discard the draft' : 'Dismiss'}
        </Button>
        <Button variant="default" onClick={onBack}>
          Back to Set up the site
        </Button>
      </Group>
      {stale === null && locked ? <LockedNote>{locked}</LockedNote> : null}
    </HeroBand>
  );
}
