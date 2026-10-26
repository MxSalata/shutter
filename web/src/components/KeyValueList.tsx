import { Text } from '@mantine/core';
import { StackTable } from './StackTable';
import type { ReactNode } from 'react';

/**
 * Label and value rows; empty values are left out. On a phone each label sits over its value (`kv-list`). A narrow
 * card gives a smaller label width.
 */
export function KeyValueList({
  rows,
  labelWidth = 190,
}: {
  rows: [string, ReactNode][];
  labelWidth?: number;
}) {
  const shown = rows.filter(([, v]) => v !== undefined && v !== null && v !== '');
  return (
    <StackTable className="kv-list" withRowBorders={false} verticalSpacing={4} highlightOnHover={false}>
      <StackTable.Tbody>
        {shown.map(([k, v]) => (
          <StackTable.Tr key={k}>
            <StackTable.Th w={labelWidth} style={{ verticalAlign: 'top', fontWeight: 500 }}>
              <Text size="sm" c="dimmed">
                {k}
              </Text>
            </StackTable.Th>
            <StackTable.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
              {typeof v === 'string' ? <Text size="sm">{v}</Text> : v}
            </StackTable.Td>
          </StackTable.Tr>
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
}
