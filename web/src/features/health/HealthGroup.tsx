import { Group, List, Stack, Text } from '@mantine/core';
import { IconCheck, IconMinus, IconX } from '@tabler/icons-react';
import { useLibrary } from '@/api/hooks';
import { CodeChip } from '@/components/CodeChip';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import { formatInt } from '@/lib/format';
import { toneText, type Tone } from '@/lib/tone';
import { useDetail } from '@/stores/appearance';
import {
  budgetLine,
  credentialChecks,
  isLong,
  licenceSentence,
  objectLines,
  type Group as GroupData,
  type Mark,
  type Report,
  type Row,
} from './report';

/** The mark's 16 px icon, in its tone; decorative, since the value cell says Yes, No or Not reported in words. */
function MarkIcon({ mark, tone }: { mark: Mark; tone: Tone | null }) {
  const colour = tone && tone !== 'neutral' ? toneText(tone) : 'var(--mantine-color-dimmed)';
  const style = { color: colour, flex: 'none' } as const;
  if (mark === 'check') return <IconCheck size={16} stroke={2.2} aria-hidden style={style} />;
  if (mark === 'x') return <IconX size={16} stroke={2.2} aria-hidden style={style} />;
  if (mark === 'dash') return <IconMinus size={16} stroke={2.2} aria-hidden style={style} />;
  return <span aria-hidden style={{ width: 16, flex: 'none' }} />;
}

/** A row's note for the engineer, which the Plain level leaves out. */
const TECHNICAL_NOTES: Record<string, string> = {
  mode: 'Set by the last scenario run or a reset; live failures are investigated in it too.',
  default_board: 'From the agent library; the generalist answers only in single investigator mode.',
};

/**
 * The board a case convenes by default, apart from the enabled agents the report counts: the library's members on the
 * default board, by role, and the enabled coordinator ("3 specialist agents and the coordinator agent").
 */
function DefaultBoardValue() {
  const library = useLibrary();
  if (!library.data) return <Text size="sm">Reading the agent library…</Text>;
  const board = library.data.filter((m) => m.enabled && m.inDefaultBoard);
  const specialists = board.filter((m) => m.role === 'specialist').length;
  // The server convenes any enabled coordinator, whether or not it is marked for the default board
  const coordinator = library.data.some((m) => m.enabled && m.role === 'coordinator');
  const others = board.filter((m) => m.role !== 'specialist' && m.role !== 'coordinator').length;
  const parts = [
    specialists ? `${specialists} specialist ${specialists === 1 ? 'agent' : 'agents'}` : '',
    coordinator ? 'the coordinator agent' : '',
    others ? `${others} other ${others === 1 ? 'agent' : 'agents'}` : '',
  ].filter(Boolean);
  return <Text size="sm">{parts.length ? parts.join(' and ') : 'No enabled agents'}</Text>;
}

/**
 * A report value: true and false as Yes and No, nothing as "Not reported", a time as a time, the licence as its
 * sentence, the stored credentials tried as one line per check (the one that does not sign in in the blocking tone),
 * a name, path or code in a chip, a number as a number, and any other object as its fields in words.
 */
function ValueView({ row, report }: { row: Row; report: Report }) {
  const { key, value, info } = row;
  if (row.virtual === 'default-board') return <DefaultBoardValue />;
  if (info.missing) return <Text size="sm">Not reported</Text>;
  if (value === true) return <Text size="sm">Yes</Text>;
  if (value === false) return <Text size="sm">No</Text>;
  if (key === 'mock_config' && value === '') return <Text size="sm">Off</Text>;
  if (typeof value === 'number')
    return (
      <Text size="sm" className="tabular">
        {formatInt(value)}
      </Text>
    );
  if (typeof value === 'string' && key.endsWith('_at') && !Number.isNaN(Date.parse(value)))
    return <Timestamp iso={value} />;
  if (key === 'license') {
    const sentence = licenceSentence(value);
    if (sentence) return <Text size="sm">{sentence}</Text>;
  }
  if (key === 'budget') {
    const line = budgetLine(value, report);
    if (line) return <Text size="sm">{line}</Text>;
  }
  if (key === 'credentials' && Array.isArray(value)) {
    if (!value.length) return <Text size="sm">None checked yet</Text>;
    return (
      <Stack gap={2}>
        {credentialChecks(value).map((c, i) => (
          <Text key={i} size="sm" c={c.ok ? undefined : toneText('blocking')} fw={c.ok ? undefined : 500}>
            {`${c.namespace} ${c.name}: ${c.status}`}
            {c.detail ? (
              <Text component="span" size="sm" c="dimmed">
                {` ${c.detail}`}
              </Text>
            ) : null}
          </Text>
        ))}
      </Stack>
    );
  }
  if (Array.isArray(value)) {
    if (!value.length) return <Text size="sm">None</Text>;
    return (
      <Group gap={6}>
        {value.map((v, i) => (
          <CodeChip key={i}>{typeof v === 'object' ? JSON.stringify(v) : String(v)}</CodeChip>
        ))}
      </Group>
    );
  }
  if (value && typeof value === 'object')
    return (
      <Stack gap={0}>
        {objectLines(value as Record<string, unknown>).map((line) => (
          <Text key={line} size="sm">
            {line}
          </Text>
        ))}
      </Stack>
    );
  const text = String(value);
  // A state word or a phrase in the text font; a name, a path or a code in a chip
  if (key === 'production_state' || key === 'credentials_state' || /\s/.test(text))
    return <Text size="sm">{text}</Text>;
  return <CodeChip>{text}</CodeChip>;
}

/** One report row: the mark and the label as the row's header, the value and its reason as the cell. */
function CheckRow({ row, report }: { row: Row; report: Report }) {
  const technical = useDetail() === 'technical';
  const { info } = row;
  const note = technical ? TECHNICAL_NOTES[row.key] : undefined;
  // A long value, a reason or a thing to do stacks under its label on a phone
  const long = isLong(row.value) || row.virtual === 'default-board' || !!info.reason || !!info.todo || !!note;
  return (
    <StackTable.Tr
      className="health-row"
      data-row={row.key}
      data-tone={info.tone === 'blocking' || info.tone === 'attention' ? info.tone : undefined}
      data-long={long ? 'true' : undefined}
    >
      <StackTable.Th>
        <Group gap={8} wrap="nowrap" align="flex-start">
          <MarkIcon mark={info.mark} tone={info.tone} />
          <Text size="sm" component="span">
            {row.label}
          </Text>
        </Group>
      </StackTable.Th>
      <StackTable.Td>
        <Stack gap={2} align="flex-start">
          <Group gap="xs" wrap="wrap">
            <ValueView row={row} report={report} />
            {info.reason ? (
              <StatusBadge
                tone={info.reason.tone}
                label={info.reason.chip}
                hint={info.reason.note}
                icon={null}
                variant="light"
              />
            ) : null}
          </Group>
          {info.todo ? (
            <Text size="sm" fw={500}>
              {info.todo}
            </Text>
          ) : null}
          {note ? (
            <Text size="xs" c="dimmed" maw="68ch">
              {note}
            </Text>
          ) : null}
        </Stack>
      </StackTable.Td>
    </StackTable.Tr>
  );
}

/**
 * A group of the report: a section with its heading, its count and its rows (so each row keeps its row header). Other,
 * the fields no group names, keeps its rows in a data disclosure, closed in both modes.
 */
export function HealthGroup({
  group,
  report,
  intro,
}: {
  group: GroupData;
  report: Report;
  /** The Agents group's sentence in the trial. */
  intro?: string;
}) {
  const { def } = group;
  const reasons = group.rows.filter((r) => r.info.reason);
  const licence = def.id === 'installation' && report.license && typeof report.license === 'object';
  const rows = (
    <StackTable className="health-rows" withRowBorders={false} verticalSpacing={4}>
      <StackTable.Tbody>
        {group.rows.map((row) => (
          <CheckRow key={row.key} row={row} report={report} />
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
  return (
    <div className="health-group" data-tone={group.edge ?? undefined} data-group={def.id}>
      <Section
        id={`health-${def.id}`}
        title={def.id === 'production' ? <Term term="production">Production</Term> : def.title}
        note={intro}
        aside={
          group.status ? (
            <StatusBadge tone={group.status.tone} label={group.status.label} size="md" />
          ) : undefined
        }
      >
        {def.id === 'other' ? (
          // The fields the groups do not name, one click away in both modes: a v1.35 report sends some twenty more
          <TechDetail
            label={`The report's other ${group.rows.length === 1 ? 'field' : `${group.rows.length} fields`}`}
            kind="data"
            defaultOpen={false}
          >
            {rows}
          </TechDetail>
        ) : (
          rows
        )}
        {reasons.length ? (
          <TechDetail label="What the dashes mean" kind="data">
            <List spacing={4} size="sm">
              {reasons.map((r) => (
                <List.Item key={r.key}>
                  <strong>{r.label}.</strong> {r.info.reason?.note}
                </List.Item>
              ))}
            </List>
          </TechDetail>
        ) : null}
        {licence ? (
          <TechDetail label="Licence fields" kind="data">
            <List spacing={2} size="sm">
              {Object.entries(report.license as Record<string, unknown>).map(([field, v]) => (
                <List.Item key={field}>
                  <CodeChip>{field}</CodeChip> {String(v)}
                </List.Item>
              ))}
            </List>
          </TechDetail>
        ) : null}
      </Section>
    </div>
  );
}
