import { Table, Text } from '@mantine/core';
import type { ReactNode } from 'react';

/** Label and value rows; empty values are left out. */
export function KeyValueList({ rows }: { rows: [string, ReactNode][] }) {
  const shown = rows.filter(([, v]) => v !== undefined && v !== null && v !== '');
  return (
    <Table withRowBorders={false} verticalSpacing={4} highlightOnHover={false}>
      <Table.Tbody>
        {shown.map(([k, v]) => (
          <Table.Tr key={k}>
            <Table.Th w={190} style={{ verticalAlign: 'top', fontWeight: 500 }}>
              <Text size="sm" c="dimmed">
                {k}
              </Text>
            </Table.Th>
            <Table.Td style={{ verticalAlign: 'top', minWidth: 0 }}>
              {typeof v === 'string' ? <Text size="sm">{v}</Text> : v}
            </Table.Td>
          </Table.Tr>
        ))}
      </Table.Tbody>
    </Table>
  );
}
