import { List, Stack, Text } from '@mantine/core';
import { useCaseDetails } from '@/api/hooks';
import type { Chain } from '@/api/types';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';

/**
 * What a decision on an incident's release covers, operation by operation: the case, the movement with its ward and
 * bed, the patient with authority, the event time and why it is still due. The chains carry no ward, bed or authority,
 * so those are read from each case once the dialog opens; a case that can't be read shows what the chain says.
 */
export function CoveredOperations({ chains }: { chains: Chain[] }) {
  const operations = chains.flatMap((chain) => chain.items.map((item) => ({ chain, item })));
  const cases = useCaseDetails(operations.map(({ item }) => item.caseId));
  return (
    <List
      size="sm"
      spacing={6}
      listStyleType="none"
      aria-label="What this decision covers"
      mah={280}
      tabIndex={0}
      style={{ overflowY: 'auto' }}
    >
      {operations.map(({ chain, item }, i) => {
        const c = cases[i]?.data;
        return (
          <List.Item key={item.caseId}>
            <Stack gap={0}>
              <Text size="sm">
                <Text span size="sm" fw={600}>
                  {item.caseId}
                </Text>
                {`: ${humanize(item.event)}${c?.ward ? ` to ${c.ward}` : ''}${c?.bed ? `, bed ${c.bed}` : ''}`}
              </Text>
              <Text size="sm">
                {`Patient ${chain.patientId ?? c?.patientId ?? ''}${c?.patientIdAuthority ? ` (${c.patientIdAuthority})` : ''}, event time `}
                <Timestamp iso={item.eventTime} span />
              </Text>
              <Text size="xs" c="dimmed">
                {item.caseHeadline || humanize(item.outcome)}
              </Text>
            </Stack>
          </List.Item>
        );
      })}
    </List>
  );
}
