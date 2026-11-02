import { List, Stack, Table, Text } from '@mantine/core';
import { useElementSize } from '@mantine/hooks';
import { useMemo, type CSSProperties } from 'react';
import type { AgentRun } from '@/api/types';
import { StackTable } from '@/components/StackTable';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { formatDuration, formatInt } from '@/lib/format';
import { hueVar, memberIdentity } from '@/lib/hues';
import { useTechnical } from '@/stores/appearance';
import {
  clockLabel,
  clockSentence,
  offsetSeconds,
  partSeconds,
  passClock,
  rowFigures,
  type ClockRow,
  type PassClock,
} from './runClock';

/** The picture's width before the page has measured it, and in tests, which have no layout. */
const FALLBACK_WIDTH = 640;
/** Below this width the names go above their bars, so a bar keeps most of the width. */
const STACK_BELOW = 420;
const BAR = 14;
/** How far a tool call's mark reaches above and below its bar, so a call of 1 ms still shows. */
const MARK_OUT = 4;
const AXIS = 24;
const TOP = 4;

/** Steps between the axis's ticks, in milliseconds: the smallest that keeps the labels apart. */
const STEPS = [500, 1_000, 2_000, 5_000, 10_000, 15_000, 20_000, 30_000, 60_000, 120_000, 300_000, 600_000];

function ticksOf(totalMs: number, px: number): { step: number; ticks: number[] } {
  const most = Math.max(2, Math.floor(px / 56));
  const step = STEPS.find((s) => totalMs / s <= most) ?? STEPS[STEPS.length - 1];
  const ticks: number[] = [];
  for (let t = 0; t <= totalMs; t += step) ticks.push(t);
  return { step, ticks };
}

const tickLabel = (t: number, step: number) =>
  step < 1_000 ? `${(t / 1000).toFixed(1)} s` : `${Math.round(t / 1000)} s`;

/**
 * The pass as a picture: one row per member, a bar in its identity hue from its start to its start plus its duration on
 * one axis in seconds from the pass's first start, and on each bar a mark per tool call at its time and width, in the
 * text colour (outlined in the attention tone when the policy refused it). The gaps between the marks are the model's
 * turns. The names sit in the text colour beside or above the bars; nothing moves.
 */
function ClockChart({ clock }: { clock: PassClock }) {
  const { ref, width: measured } = useElementSize<HTMLDivElement>();
  const width = Math.round(measured) || FALLBACK_WIDTH;
  const stacked = width < STACK_BELOW;
  const longest = Math.max(...clock.rows.map((r) => r.name.length));
  const gutter = stacked ? 0 : Math.min(Math.round(width * 0.4), Math.max(80, Math.ceil(longest * 6.8) + 12));
  // Room for half the first tick's label and half the last one's, so no word leaves the picture
  const left = gutter + 16;
  const right = width - 20;
  const rowH = stacked ? 44 : 30;
  const height = TOP + clock.rows.length * rowH + AXIS;
  const base = height - AXIS;
  const x = (t: number) => left + (clock.totalMs ? (t / clock.totalMs) * (right - left) : 0);
  const { step, ticks } = ticksOf(clock.totalMs, right - left);
  return (
    <div ref={ref} className="run-clock">
      <svg
        role="img"
        aria-label={clockLabel(clock)}
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        data-testid="run-clock"
      >
        {ticks.map((t) => (
          <line key={t} className="run-clock-grid" x1={x(t)} x2={x(t)} y1={TOP} y2={base} />
        ))}
        {clock.rows.map((row, i) => {
          const y0 = TOP + i * rowH;
          const barY = stacked ? y0 + 22 : y0 + (rowH - BAR) / 2;
          const barX = x(row.start);
          const barW = Math.max(2, x(row.end) - barX);
          return (
            <g key={row.key} data-row={row.member}>
              <text
                className="run-clock-label"
                x={0}
                y={stacked ? y0 + 12 : barY + BAR / 2}
                dominantBaseline="central"
              >
                {row.name}
              </text>
              <rect
                className="run-clock-bar"
                data-member={row.member}
                x={barX}
                y={barY}
                width={barW}
                height={BAR}
                rx={3}
                style={{ ['--mark-hue' as string]: hueVar(memberIdentity(row.member).hue) } as CSSProperties}
              />
              {row.marks.map((m) => {
                const least = m.refused ? 6 : 2;
                const w = Math.max(least, x(m.to) - x(m.from));
                // A mark at the very end of its bar stays on the bar
                const mx = Math.max(barX, Math.min(x(m.from), barX + barW - w));
                return (
                  <rect
                    key={m.seq}
                    className="run-clock-mark"
                    data-refused={m.refused || undefined}
                    data-seq={m.seq}
                    x={mx}
                    y={barY - MARK_OUT}
                    width={w}
                    height={BAR + 2 * MARK_OUT}
                    rx={1}
                  >
                    <title>{`${m.name}${m.refused ? ', refused' : `, ${formatDuration(m.durationMs)}`}`}</title>
                  </rect>
                );
              })}
            </g>
          );
        })}
        <g className="run-clock-axis">
          <line x1={left} x2={right} y1={base} y2={base} />
          {ticks.map((t) => (
            <g key={t}>
              <line x1={x(t)} x2={x(t)} y1={base} y2={base + 4} />
              <text className="run-clock-tick" x={x(t)} y={base + 16} textAnchor="middle">
                {tickLabel(t, step)}
              </text>
            </g>
          ))}
        </g>
      </svg>
    </div>
  );
}

/** What the marks mean, or why there are none. */
function legendOf(clock: PassClock): string {
  const marked = clock.rows.some((r) => r.marks.length);
  const refused = clock.rows.some((r) => r.marks.some((m) => m.refused));
  const calls = clock.rows.some((r) => r.calls > 0);
  if (marked)
    return `Each bar is one agent's run and each mark on it a tool call; the gaps between the marks are the model's turns.${refused ? ' An outlined mark is a call the policy refused before it ran.' : ''}`;
  if (calls && clock.precision === 's')
    return "Each bar is one agent's run. Its start is recorded to the second, so its tool calls are not drawn.";
  if (calls)
    return "Each bar is one agent's run. No tool-call times are recorded, so the bars carry no marks.";
  return "Each bar is one agent's run.";
}

const notRecorded = (v: number | undefined, show: (n: number) => string) =>
  v === undefined ? 'not recorded' : show(v);

/** The same facts as the picture, for a reader who would rather read them, and for a screen reader. */
function ClockTable({ clock }: { clock: PassClock }) {
  const tokens = clock.rows.some((r) => r.reasoningTokens !== undefined);
  const calls = (r: ClockRow) =>
    `${formatInt(r.calls)}${r.refused ? `, ${formatInt(r.refused)} refused` : ''}`;
  return (
    <Table.ScrollContainer minWidth={560} className="stack-scroll">
      <StackTable verticalSpacing="xs" fz="sm" className="stack-table">
        <Table.Caption>
          Starts in seconds from the pass&apos;s first start; model and tool time as IRIS AI Hub counted them.
        </Table.Caption>
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Agent</StackTable.Th>
            <StackTable.Th ta="right">Start</StackTable.Th>
            <StackTable.Th ta="right">Took</StackTable.Th>
            <StackTable.Th ta="right">Tool calls</StackTable.Th>
            <StackTable.Th ta="right">Model time</StackTable.Th>
            <StackTable.Th ta="right">Tool time</StackTable.Th>
            {tokens ? <StackTable.Th ta="right">Reasoning tokens</StackTable.Th> : null}
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {clock.rows.map((r) => (
            <StackTable.Tr key={r.key}>
              <StackTable.Th scope="row" fw={500}>
                {r.name}
              </StackTable.Th>
              <StackTable.Td ta="right" className="tabular" data-label="Start">
                {offsetSeconds(r.start, clock.precision)}
              </StackTable.Td>
              <StackTable.Td ta="right" className="tabular" data-label="Took">
                {formatDuration(r.durationMs)}
              </StackTable.Td>
              <StackTable.Td ta="right" className="tabular" data-label="Tool calls">
                {calls(r)}
              </StackTable.Td>
              <StackTable.Td ta="right" className="tabular" data-label="Model time">
                {notRecorded(r.llmMs, partSeconds)}
              </StackTable.Td>
              <StackTable.Td ta="right" className="tabular" data-label="Tool time">
                {notRecorded(r.toolMs, partSeconds)}
              </StackTable.Td>
              {tokens ? (
                <StackTable.Td ta="right" className="tabular" data-label="Reasoning tokens">
                  {notRecorded(r.reasoningTokens, formatInt)}
                </StackTable.Td>
              ) : null}
            </StackTable.Tr>
          ))}
        </StackTable.Tbody>
      </StackTable>
    </Table.ScrollContainer>
  );
}

/**
 * "When each agent worked": the board pass's runs on one time axis, under the specialists' cards and above the
 * coordinator's, as a disclosure open in Technical and closed in Plain. The picture says it in one sentence for a
 * screen reader, the Plain sentence under it says it for everyone, Technical adds each run's split between the model
 * and the tools, and "As a table" gives the same facts. A pass whose rows cannot draw it honestly shows nothing
 * (`passClock`).
 */
export function RunTimeline({ runs }: { runs: AgentRun[] | null | undefined }) {
  const clock = useMemo(() => passClock(runs), [runs]);
  const technical = useTechnical();
  if (!clock) return null;
  return (
    <TechDetail kind="data" label="When each agent worked" tour="case-run-timeline">
      <Stack gap="xs" data-testid="run-timeline">
        <ClockChart clock={clock} />
        <Text size="xs" c="dimmed">
          {"Seconds from the pass's first start, "}
          <Timestamp iso={clock.startedAt} size="xs" c="dimmed" />
          {clock.precision === 's' ? ', to the second' : ''}.
        </Text>
        <Text size="sm" maw="68ch" data-testid="run-timeline-sentence">
          {clockSentence(clock)}
        </Text>
        {technical ? (
          <List size="sm" spacing={2} data-testid="run-timeline-figures">
            {clock.rows.map((r) => (
              <List.Item key={r.key}>{`${r.name}: ${rowFigures(r)}`}</List.Item>
            ))}
          </List>
        ) : null}
        <Text size="sm" c="dimmed" maw="68ch">
          {legendOf(clock)}
        </Text>
        {/* The same facts in rows and columns; closed in both modes, since Technical already lists each run's split */}
        <TechDetail kind="data" defaultOpen={false} label="As a table">
          <ClockTable clock={clock} />
        </TechDetail>
      </Stack>
    </TechDetail>
  );
}
