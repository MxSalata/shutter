import { Anchor, Button, Group, List, Table, Text } from '@mantine/core';
import { useEffect, useRef } from 'react';
import { Link } from 'react-router';
import { LockedNote } from '@/components/LockedSave';
import { CodeChip } from '@/components/CodeChip';
import { HeroBand } from '@/components/HeroBand';
import { StatusNotice } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { fieldLabel, valueLabel, type Applied, type SuggestedChange } from './suggestion';

/** Why a suggestion could not be pre-filled, in words. */
function refusal(caseId: string, s: SuggestedChange | undefined, r: Exclude<Applied, { ok: true }>): string {
  if (r.reason === 'unreadable' || !s)
    return r.reason === 'unreadable'
      ? `The What-if facts of case ${caseId} could not be read, so nothing was pre-filled. Open the case again and try once more.`
      : `Case ${caseId} has no such What-if fact now, so nothing was pre-filled. Open the case again for its current facts.`;
  const label = fieldLabel(s.field, s.receiver);
  switch (r.reason) {
    case 'invalid':
      return `The site profile would refuse this change${s.problem ? `: ${s.problem}` : ''}. Nothing was pre-filled.`;
    case 'stale':
      if (r.current === undefined)
        return `The profile has changed since the suggestion was made: ${label.toLowerCase()} no longer holds ${valueLabel(s.field, s.from)}. Nothing was pre-filled; open the case again for facts read against the current profile.`;
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
 * and in the draft, why and what it reaches, all read from the case's facts. Saving goes through the page's own review
 * and save, approvers only. It is a hero band with an attention edge (a person is needed to decide) whose heading
 * takes focus when the reader arrives from the case.
 */
export function SuggestionCard({
  caseId,
  s,
  result,
  version,
  locked = null,
  onReview,
  onDiscard,
}: {
  caseId: string;
  /** The change read from the case's facts; absent when they could not be read or no longer name the fact. */
  s?: SuggestedChange;
  result: Applied;
  version: number;
  /** Why this reader cannot save (`saveLocked`): the change is reviewed as an approver's, and the save is locked. */
  locked?: string | null;
  onReview: () => void;
  onDiscard: () => void;
}) {
  const heading = useRef<HTMLElement>(null);
  // Arriving from a case, the reader lands on the suggestion, not at the top of the form
  useEffect(() => heading.current?.focus(), []);
  const back = `/cases/${encodeURIComponent(caseId)}?ask=1`;
  return (
    <HeroBand
      tone="attention"
      id="site-suggestion"
      statementAs="h2"
      statement={s ? `A suggested change from case ${caseId}` : 'A suggested change'}
      statementProps={{ id: 'site-suggestion-title', tabIndex: -1, ref: heading }}
    >
      {result.ok && s ? (
        <>
          <Text size="md">
            The form below is a draft with this one change. Nothing is saved until an approver reviews and
            saves it.
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
                  {fieldLabel(s.field, s.receiver)} <CodeChip>{s.field}</CodeChip>
                </Table.Th>
                <Table.Td>{valueLabel(s.field, s.from)}</Table.Td>
                <Table.Td fw={700}>{valueLabel(s.field, s.to)}</Table.Td>
              </Table.Tr>
            </Table.Tbody>
          </Table>
          {s.why ? <Text size="md">What the case would have done: {s.why}</Text> : null}
          {s.affects?.length ? (
            <>
              <Text size="md">It would apply to:</Text>
              <List size="sm" spacing={2}>
                {s.affects.map((a) => (
                  <List.Item key={a}>{a}</List.Item>
                ))}
              </List>
            </>
          ) : null}
          <TechDetail label="More about this change" kind="explain">
            <Text size="sm" maw="68ch">
              Earlier approvals stay tied to the profile version they were made under; a saved change gives a
              new version, and they come back to a person at release.
            </Text>
          </TechDetail>
        </>
      ) : (
        <StatusNotice tone="attention" title="Not pre-filled">
          {refusal(caseId, s, result as Exclude<Applied, { ok: true }>)}
        </StatusNotice>
      )}
      <Group gap="sm">
        {result.ok ? <Button onClick={onReview}>Review and save…</Button> : null}
        <Button variant="default" onClick={onDiscard}>
          {result.ok ? 'Discard the suggestion' : 'Dismiss'}
        </Button>
        <Anchor component={Link} to={back} size="sm">
          Back to case {caseId}
        </Anchor>
      </Group>
      {result.ok && locked ? <LockedNote>{locked}</LockedNote> : null}
    </HeroBand>
  );
}
