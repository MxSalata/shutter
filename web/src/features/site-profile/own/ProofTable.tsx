import { List, Stack, Table, Text } from '@mantine/core';
import type { SiteEntryProofResult } from '@/api/types';
import { StatusBadge } from '@/components/StatusBadge';
import { useTechnical } from '@/stores/appearance';
import { GROUP_WORDS, groupsOf, impactLine } from './words';

/**
 * A proof's result as the core answered it (P1, P2, P4): each fixture, whether the entry answered as expected and which
 * entry leads there, then what the last stored cases would have done without it, grouped. The same table shows a
 * stored proof, the proof a proposal was made on and a preview's, which keeps nothing.
 */
export function ProofTable({
  proof,
  preview = false,
  testId = 'own-proof',
}: {
  proof: SiteEntryProofResult;
  /** A preview: it says so, since nothing was kept. */
  preview?: boolean;
  testId?: string;
}) {
  const technical = useTechnical();
  const retire = proof.action === 'retire';
  return (
    <Stack gap="xs" data-testid={testId}>
      <StatusBadge
        tone={proof.passed ? 'positive' : 'blocking'}
        label={proof.passed ? 'The proof passes' : 'The proof does not pass'}
        hint={
          preview
            ? 'A try: nothing was kept, and a draft is proved again before it is sent for approval'
            : 'Kept with the digest it proved; an approval runs it again'
        }
      />
      {proof.problems.length ? (
        <List size="sm" spacing={2} data-testid={`${testId}-problems`}>
          {proof.problems.map((p) => (
            <List.Item key={p}>{p}</List.Item>
          ))}
        </List>
      ) : null}
      {proof.fixtures.length ? (
        <Table
          withTableBorder
          verticalSpacing={4}
          horizontalSpacing="xs"
          fz="sm"
          data-testid={`${testId}-fixtures`}
          style={{ tableLayout: 'fixed', width: '100%' }}
        >
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Case</Table.Th>
              <Table.Th>Expected</Table.Th>
              <Table.Th>As expected</Table.Th>
              <Table.Th>Leads there</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {proof.fixtures.map((f) => (
              <Table.Tr key={f.case}>
                <Table.Td style={{ overflowWrap: 'anywhere' }}>{f.case}</Table.Td>
                <Table.Td>{f.expect === 'match' ? 'To catch' : 'To leave alone'}</Table.Td>
                <Table.Td>
                  <Text span inherit fw={600} c={f.ok ? undefined : 'red'}>
                    {f.ok ? 'Yes' : 'No'}
                  </Text>
                  {f.source === 'frozen' ? ' (from its frozen conditions: the case is gone)' : ''}
                </Table.Td>
                <Table.Td style={{ overflowWrap: 'anywhere' }}>
                  {f.expect === 'match' ? f.lead || 'nothing' : f.holds ? 'it would match' : 'not this entry'}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      ) : retire ? null : (
        <Text size="sm">No fixture yet: name a case it must catch and a case it must leave alone.</Text>
      )}
      {technical && proof.fixtures.length ? (
        <List size="xs" spacing={0} c="dimmed">
          {proof.fixtures.map((f) => (
            <List.Item key={f.case}>{`${f.case}: ${f.text}`}</List.Item>
          ))}
        </List>
      ) : null}
      {proof.impact ? (
        <Stack gap={2} data-testid={`${testId}-impact`}>
          <Text size="sm">{impactLine(proof.impact, proof.action)}</Text>
          {groupsOf(proof.impact).length ? (
            <List size="sm" spacing={2}>
              {groupsOf(proof.impact).map((g) => (
                <List.Item key={g.group}>
                  {`${GROUP_WORDS[g.group].charAt(0).toUpperCase()}${GROUP_WORDS[g.group].slice(1)}: `}
                  <Text span inherit style={{ overflowWrap: 'anywhere' }}>
                    {g.cases.join(', ')}
                  </Text>
                </List.Item>
              ))}
            </List>
          ) : null}
        </Stack>
      ) : null}
    </Stack>
  );
}
