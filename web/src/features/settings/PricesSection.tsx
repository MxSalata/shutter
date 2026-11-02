import { ActionIcon, Group, Stack, Text, Tooltip } from '@mantine/core';
import { IconInfoCircle } from '@tabler/icons-react';
import type { ModelPrice } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { formatUsd } from '@/lib/format';
import { HINT_EVENTS } from '@/theme';
import { fullSource, shortSource, sourcesOf } from './settingsText';

/** "List price, read 16 Oct 2026", with the stored source in full on hover, keyboard focus or a tap. */
function Source({ p }: { p: ModelPrice }) {
  const full = fullSource(p);
  return (
    <Group gap={4} wrap="nowrap" align="center">
      <Text size="sm">{shortSource(p)}</Text>
      <Tooltip label={full} multiline maw={320} events={HINT_EVENTS}>
        <ActionIcon
          variant="subtle"
          color="gray"
          size="sm"
          aria-label={`Source of ${p.model}'s prices: ${full}`}
        >
          <IconInfoCircle size={16} aria-hidden />
        </ActionIcon>
      </Tooltip>
    </Group>
  );
}

/**
 * The prices costs are computed from, per million tokens, as stored: one short source for each (the stored string in
 * a tooltip and, in full, in the data detail), so the table is figures and not four copies of a sentence.
 */
export function PricesSection({ prices }: { prices: ModelPrice[] }) {
  const sources = sourcesOf(prices);
  return (
    <Section
      id="settings-prices"
      title="Prices used for costs"
      note="Per million tokens, as stored; costs are estimates from them, not invoices."
    >
      {prices.length === 0 ? (
        <Text size="sm" c="dimmed">
          No prices are stored, so costs cannot be estimated.
        </Text>
      ) : (
        <StackTable aria-label="Prices per million tokens" className="stack-table">
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th>Model</StackTable.Th>
              <StackTable.Th ta="right">Input</StackTable.Th>
              <StackTable.Th ta="right">Output</StackTable.Th>
              <StackTable.Th ta="right">
                <Term term="cache-read">Cache read</Term>
              </StackTable.Th>
              <StackTable.Th ta="right">Cache write</StackTable.Th>
              <StackTable.Th>Source</StackTable.Th>
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {prices.map((p) => (
              <StackTable.Tr key={p.model}>
                <StackTable.Td data-label="Model">
                  <CodeChip>{p.model}</CodeChip>
                </StackTable.Td>
                <StackTable.Td data-label="Input" ta="right" className="tabular">
                  {formatUsd(p.inputPerMTok)}
                </StackTable.Td>
                <StackTable.Td data-label="Output" ta="right" className="tabular">
                  {formatUsd(p.outputPerMTok)}
                </StackTable.Td>
                <StackTable.Td data-label="Cache read" ta="right" className="tabular">
                  {formatUsd(p.cacheReadPerMTok)}
                </StackTable.Td>
                <StackTable.Td data-label="Cache write" ta="right" className="tabular">
                  {formatUsd(p.cacheWritePerMTok)}
                </StackTable.Td>
                <StackTable.Td data-label="Source">
                  <Source p={p} />
                </StackTable.Td>
              </StackTable.Tr>
            ))}
          </StackTable.Tbody>
        </StackTable>
      )}
      {sources.length ? (
        <TechDetail label="Where these prices come from" kind="explain">
          <Stack gap="xs">
            {sources.map((s) => (
              <Text size="sm" key={s.source}>
                {s.source}:{' '}
                {s.models.map((m, i) => (
                  <span key={m}>
                    {i > 0 ? ', ' : ''}
                    <CodeChip>{m}</CodeChip>
                  </span>
                ))}
              </Text>
            ))}
          </Stack>
        </TechDetail>
      ) : null}
    </Section>
  );
}
