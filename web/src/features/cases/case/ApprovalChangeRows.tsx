import { Stack, Text } from '@mantine/core';
import { StackTable } from '@/components/StackTable';
import { Timestamp } from '@/components/Timestamp';
import { approvalChange, type ApprovalEvidence, type ReviewedPlan } from './approvalChange';
import type { ActionCase } from './planAction';

/**
 * What releasing the plan changes at the receiver, in two rows: what the evidence read there, with its time, and what
 * is expected if this plan is released, with where that expectation comes from. The Approval section and the review
 * dialog both draw these rows from the one derivation (`approvalChange`), so their words can't part. Laid out as
 * `KeyValueList` lays its rows out, on a phone each label over its value.
 */
export function ApprovalChangeRows({
  view,
  c,
  snapshot,
}: {
  view: ReviewedPlan;
  c: ActionCase;
  snapshot: ApprovalEvidence;
}) {
  const { held, readAt, expected, basis, notes } = approvalChange(view, c, snapshot);
  return (
    <Stack gap={4} data-testid="approval-change">
      <StackTable className="kv-list" withRowBorders={false} verticalSpacing={4} highlightOnHover={false}>
        <StackTable.Tbody>
          <StackTable.Tr>
            <StackTable.Th w={190} style={{ verticalAlign: 'top', fontWeight: 500 }}>
              <Text size="sm" c="dimmed">
                {readAt ? 'Receiver state read at ' : 'Receiver state when read'}
                {readAt ? <Timestamp iso={readAt} size="sm" c="dimmed" /> : null}
              </Text>
            </StackTable.Th>
            <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
              <Text size="sm">{held}</Text>
            </StackTable.Td>
          </StackTable.Tr>
          <StackTable.Tr>
            <StackTable.Th w={190} style={{ verticalAlign: 'top', fontWeight: 500 }}>
              <Text size="sm" c="dimmed">
                Expected if this plan is released
              </Text>
            </StackTable.Th>
            <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
              <Text size="sm" fw={600}>
                {expected}
                {basis ? (
                  <Text span inherit fw={400} c="dimmed">
                    {` (${basis})`}
                  </Text>
                ) : null}
              </Text>
            </StackTable.Td>
          </StackTable.Tr>
        </StackTable.Tbody>
      </StackTable>
      {notes.map((n) => (
        <Text key={n} size="sm">
          {n}
        </Text>
      ))}
    </Stack>
  );
}
