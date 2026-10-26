import { Anchor, Button, Card, Code, Group, List, Stack, Table, Text, Title } from '@mantine/core';
import { useEffect, useRef } from 'react';
import { Link } from 'react-router';
import { StatusNotice } from '@/components/StatusBadge';
import { fieldLabel, valueLabel, type Applied, type SuggestedChange } from './suggestion';

/** Why a suggestion could not be pre-filled, in words. */
function refusal(s: SuggestedChange, r: Exclude<Applied, { ok: true }>): string {
  const label = fieldLabel(s.field, s.receiver);
  switch (r.reason) {
    case 'stale':
      return `The profile has changed since the suggestion was made: ${label.toLowerCase()} is now ${valueLabel(s.field, r.current)}, not ${valueLabel(s.field, s.from)}. Nothing was pre-filled; open the case again for facts read against the current profile.`;
    case 'already':
      return `The profile already sets ${label.toLowerCase()} to ${valueLabel(s.field, s.to)}: there is nothing to change.`;
    case 'no_receiver':
      return `The profile has no receiver named ${s.receiver ?? ''}, so nothing was pre-filled.`;
    default:
      return `This page cannot pre-fill ${s.field}. Nothing was pre-filled; change it by hand if you decide to.`;
  }
}

/**
 * A change suggested by a case's What-if card, shown above the form as a pre-filled draft: the setting, its value now
 * and in the draft, why and what it reaches. Saving goes through the page's own review and save, approvers only.
 */
export function SuggestionCard({
  s,
  result,
  version,
  editable,
  onReview,
  onDiscard,
}: {
  s: SuggestedChange;
  result: Applied;
  version: number;
  editable: boolean;
  onReview: () => void;
  onDiscard: () => void;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  // Arriving from a case, the reader lands on the suggestion, not at the top of the form
  useEffect(() => heading.current?.focus(), []);
  const label = fieldLabel(s.field, s.receiver);
  const back = s.caseId ? `/cases/${encodeURIComponent(s.caseId)}?ask=1` : null;
  return (
    <Card
      padding="md"
      withBorder
      component="section"
      aria-labelledby="site-suggestion-title"
      id="site-suggestion"
      className="ask-whatif"
    >
      <Stack gap="sm">
        <Title order={2} fz="lg" id="site-suggestion-title" tabIndex={-1} ref={heading}>
          {s.caseId ? `A suggested change from case ${s.caseId}` : 'A suggested change'}
        </Title>
        {result.ok ? (
          <>
            <Text size="sm">
              The form below is a draft with this one change. Nothing is saved until an approver reviews and
              saves it, and earlier approvals stay tied to the profile version they were made under.
            </Text>
            <Table withTableBorder variant="vertical" layout="fixed" captionSide="top">
              <Table.Caption>The change in this draft</Table.Caption>
              <Table.Thead>
                <Table.Tr>
                  <Table.Th scope="col">Setting</Table.Th>
                  <Table.Th scope="col">Now, version {version}</Table.Th>
                  <Table.Th scope="col">In this draft</Table.Th>
                </Table.Tr>
              </Table.Thead>
              <Table.Tbody>
                <Table.Tr>
                  <Table.Th scope="row" fw={400}>
                    {label} <Code>{s.field}</Code>
                  </Table.Th>
                  <Table.Td>{valueLabel(s.field, s.from)}</Table.Td>
                  <Table.Td fw={700}>{valueLabel(s.field, s.to)}</Table.Td>
                </Table.Tr>
              </Table.Tbody>
            </Table>
            {s.why ? <Text size="sm">What the case would have done: {s.why}</Text> : null}
            {s.affects?.length ? (
              <>
                <Text size="sm">It would apply to:</Text>
                <List size="sm" spacing={2}>
                  {s.affects.map((a) => (
                    <List.Item key={a}>{a}</List.Item>
                  ))}
                </List>
              </>
            ) : null}
          </>
        ) : (
          <StatusNotice tone="attention" title="Not pre-filled">
            {refusal(s, result)}
          </StatusNotice>
        )}
        <Group gap="sm">
          {result.ok && editable ? <Button onClick={onReview}>Review and save…</Button> : null}
          <Button variant="default" onClick={onDiscard}>
            {result.ok ? 'Discard the suggestion' : 'Dismiss'}
          </Button>
          {back ? (
            <Anchor component={Link} to={back} size="sm">
              Back to case {s.caseId}
            </Anchor>
          ) : null}
        </Group>
        {result.ok && !editable ? (
          <Text size="sm" c="dimmed">
            Saving it needs the approver role: an approver reviews and saves it.
          </Text>
        ) : null}
      </Stack>
    </Card>
  );
}
