import { Table, Text, Tooltip, UnstyledButton } from '@mantine/core';
import { useId, useState } from 'react';
import { hueVar, type Hue } from '@/lib/hues';
import { HINT_EVENTS } from '@/theme';

export interface ComparisonBar {
  /** Who, in words: "The board", "Simple rules". */
  label: string;
  value: number;
  /** The actor's identity hue (the board violet); gray for the baseline, never a status colour. */
  hue: Hue;
  /** The bar's tooltip ("Impact Analysis: 23 of 24 scored passes"); "<label>: <value> of <of>" when absent. */
  hint?: string;
}

/**
 * Actors compared on one measure and one base: one bar each, the label left and the value right in the text colour
 * (direct labels, no legend), a recessive baseline only, and a caption that names the base ("on the same 11
 * failures"). Two denominators are two separate ComparisonBars, never one axis. "Show as a table" swaps in a real
 * table. Plain HTML and CSS: no chart library.
 */
export function ComparisonBars({
  bars,
  of,
  caption,
  unit,
}: {
  bars: ComparisonBar[];
  /** The base every bar is out of. */
  of: number;
  /** What the figures are, on which base. */
  caption: string;
  /** The value's words after the number in the table and the tooltips ("of 11"), when not "of <of>". */
  unit?: string;
}) {
  const [table, setTable] = useState(false);
  const id = useId();
  const valueWords = (b: ComparisonBar) => `${b.value} ${unit ?? `of ${of}`}`;
  return (
    <figure style={{ margin: 0 }} aria-labelledby={id}>
      {table ? (
        <Table withRowBorders={false} verticalSpacing={2} fz="sm" aria-labelledby={id}>
          <Table.Thead>
            <Table.Tr>
              <Table.Th>Who</Table.Th>
              <Table.Th ta="right">Figure</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {bars.map((b) => (
              <Table.Tr key={b.label}>
                <Table.Td>{b.label}</Table.Td>
                <Table.Td ta="right" className="tabular">
                  {valueWords(b)}
                </Table.Td>
              </Table.Tr>
            ))}
          </Table.Tbody>
        </Table>
      ) : (
        <div className="comparison-bars">
          {bars.map((b) => (
            <ComparisonRow key={b.label} bar={b} of={of} words={valueWords(b)} />
          ))}
        </div>
      )}
      <Text component="figcaption" id={id} size="xs" c="dimmed" mt={4}>
        {caption}
      </Text>
      <UnstyledButton
        className="tech-detail-toggle"
        aria-pressed={table}
        onClick={() => setTable((t) => !t)}
        mt={2}
      >
        {table ? 'Show as bars' : 'Show as a table'}
      </UnstyledButton>
    </figure>
  );
}

function ComparisonRow({ bar, of, words }: { bar: ComparisonBar; of: number; words: string }) {
  const share = of > 0 ? Math.max(0, Math.min(1, bar.value / of)) : 0;
  return (
    <>
      <Text size="sm" span>
        {bar.label}
      </Text>
      <Tooltip label={bar.hint ?? `${bar.label}: ${words}`} events={HINT_EVENTS}>
        <span
          className="comparison-track"
          role="img"
          tabIndex={0}
          aria-label={bar.hint ?? `${bar.label}: ${words}`}
        >
          <span
            className="comparison-bar"
            style={{ display: 'block', width: `${share * 100}%`, ['--mark-hue' as string]: hueVar(bar.hue) }}
          />
        </span>
      </Tooltip>
      <Text size="sm" span className="tabular" ta="right">
        {bar.value}
      </Text>
    </>
  );
}
