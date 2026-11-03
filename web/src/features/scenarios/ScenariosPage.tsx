import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Chip,
  Group,
  Loader,
  Radio,
  SimpleGrid,
  Stack,
  Table,
  Text,
  Title,
  Tooltip,
  VisuallyHidden,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconFlask2, IconPlayerPlay, IconRefresh, IconShieldX } from '@tabler/icons-react';
import { useMemo, useState } from 'react';
import { Link } from 'react-router';
import {
  isPlaying,
  useCan,
  useCases,
  useHealth,
  useResetScenarios,
  useRunScenario,
  useScenarios,
  useSiteProfile,
} from '@/api/hooks';
import { scenariosHidden } from '@/api/can';
import type { CaseSummary, Mode, Scenario, ScenarioRun } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { byEnv } from '@/env/copy';
import { PageHeader } from '@/components/PageHeader';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { ExpectedMark } from '@/components/ExpectedMark';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { StackTable } from '@/components/StackTable';
import { caseOutcome, caseState, proposedWrites, writes } from '@/lib/status';
import { describeError } from '@/lib/errors';
import { formatAge, humanize } from '@/lib/format';
import { playedFor } from '@/lib/proof';
import type { Tone } from '@/lib/tone';
import { useTechnical } from '@/stores/appearance';
import { HINT_EVENTS } from '@/theme';
import { MoreAbout } from './MoreAbout';
import { StartHere } from './StartHere';
import { ModeName, ScenariosHero, TryFirst } from './TryFirst';
import { hl7Events, recordedLine, SCENARIOS_LEAD, splitSummary } from './scenarioText';

const ALL_MODES: { value: Mode; label: string; hint: string }[] = [
  {
    value: 'board',
    label: 'Board',
    hint: 'Three specialist agents review the evidence in parallel; a coordinator agent proposes one plan.',
  },
  {
    value: 'policy',
    label: 'Site policy',
    hint: "The scenario catalogue and the site's profile settle the cases they know; the board takes the rest.",
  },
  {
    value: 'single',
    label: 'Single investigator',
    hint: 'One generalist agent looks at everything and proposes the plan.',
  },
  {
    value: 'rules',
    label: 'Rules only',
    hint: 'No agents: resend unchanged unless the gate objects. The baseline to compare with.',
  },
];

/** The demo leaves out the single investigator: its runs were never recorded, so it has nothing to replay. */
const MODES = TRIAL ? ALL_MODES.filter((m) => m.value !== 'single') : ALL_MODES;

const modeLabel = (mode: Mode) => ALL_MODES.find((m) => m.value === mode)?.label ?? humanize(mode);

/** What every mode keeps, said once above the modes. */
const MODES_INTRO =
  'The mode chooses who proposes the plan; the gate, the rehearsal and the release are the same in every mode.';

/** Whether the scenario is defined for the mode: one that names its modes isn't for the others. */
const definedFor = (s: Scenario, mode: Mode) => !s.expected?.modes || s.expected.modes.includes(mode);

/** Why nothing can be played on a site install: the server switches the Scenario Player off (CONTRACTS 12). */
const PLAYER_OFF = 'The Scenario Player is switched off on a site install, which has no demo';

/**
 * The run's state above the list; once done, where to look: on an instance the production carries on from the files,
 * in the trial the scenario's case is the recorded one, already in its final state.
 */
function RunBanner({ run, latest }: { run: ScenarioRun; latest: string | undefined }) {
  if (run.state === 'queued')
    return (
      <Alert
        color="blue"
        variant="light"
        icon={<Loader size={16} />}
        title={`${run.scenario} is queued (${humanize(run.mode)})`}
      >
        <Text size="sm">The scenario player starts it in a moment.</Text>
      </Alert>
    );
  if (run.state === 'running')
    return (
      <Alert
        color="blue"
        variant="light"
        icon={<Loader size={16} />}
        title={`Playing ${run.scenario} (${humanize(run.mode)})`}
      >
        <Text size="sm">
          {run.step ? `Now ${run.step}.` : 'Starting.'} Files delivered so far:{' '}
          {run.files.length ? run.files.join(', ') : 'none'}.
        </Text>
      </Alert>
    );
  if (run.state === 'done')
    return (
      <Alert
        color="blue"
        variant="light"
        title={`${run.scenario} played (${humanize(run.mode)}), ${formatAge(run.finishedAt)}`}
      >
        <Text size="sm">
          Delivered {run.files.join(', ') || 'no files'}.
          {run.timeouts.length ? ` The case did not reach ${run.timeouts.join(', ')} in time.` : ''}{' '}
          {byEnv({
            live: 'The production does the rest: follow the case below.',
            trial: latest
              ? `Its case is ${latest}, replayed from the recording, so it is already in its final state: open it from the row below.`
              : 'Its case is replayed from the recording: open it from the row below.',
          })}
        </Text>
      </Alert>
    );
  return (
    <Alert
      color="red"
      variant="light"
      title={`${run.scenario} ${run.state === 'interrupted' ? 'was interrupted' : 'failed'}`}
    >
      <Text size="sm">{run.error || 'The background run stopped before its last step.'}</Text>
    </Alert>
  );
}

/** The writes a scenario should make, as a badge: conditional writes are proposed, never made before the gate. */
function WritesBadge({ n, inAll = false }: { n: number; inAll?: boolean }) {
  if (!n) return <StatusBadge {...writes(0)} label="Nothing written" hint={undefined} />;
  return (
    <StatusBadge
      {...proposedWrites(n)}
      label={`${n} conditional write${n === 1 ? '' : 's'}${inAll ? ' in all' : ''}`}
      hint={undefined}
    />
  );
}

/**
 * What should happen in the mode: the scenario's expected outcome with the mode's own additions (expected.by_mode),
 * as badges on one line, the code the gate or the dispatch should stop on as a code beside its words, the plain
 * sentence, and what the evaluation recorded when the comparison played it.
 */
function ExpectedOutcome({ s, mode }: { s: Scenario; mode: Mode }) {
  if (!s.expected) return null;
  const e = { ...s.expected, ...s.expected.by_mode?.[mode] };
  const recorded = recordedLine(playedFor(s.id));
  const recordedText = recorded ? (
    <Text size="sm" c="dimmed">
      {recorded}
    </Text>
  ) : null;
  // An incident has no single end state: it says how many encounters it opens and the writes their chains make
  const encounters = e.encounters ?? [];
  const incident = !!e.incident && encounters.length > 0;
  const incidentWrites = encounters.reduce((n, x) => n + (x.writes || 0), 0);
  // One failure at several receivers: each receiver's case ends its own way
  if (e.by_receiver) {
    return (
      <Stack gap={4}>
        {Object.entries(e.by_receiver).map(([receiver, x]) => (
          <Group key={receiver} gap={6}>
            <Text size="sm" fw={600}>
              {receiver}
            </Text>
            <DispositionBadge disposition={x.disposition} />
            <WritesBadge n={x.write ? 1 : 0} />
            {x.outcome === 'correct_history' ? (
              <Text size="sm" c="dimmed">
                with the steps that correct its history
              </Text>
            ) : null}
          </Group>
        ))}
        <Text size="sm">
          One case per receiver.{' '}
          {e.final_state ? `Each ends ${e.final_state}${e.final_ward ? ` in ${e.final_ward}` : ''}.` : ''}
        </Text>
        {recordedText}
      </Stack>
    );
  }
  return (
    <Stack gap={4}>
      <Group gap={6}>
        <DispositionBadge disposition={e.disposition ?? ''} focusable={false} />
        {e.acceptable
          ?.filter((a) => a !== e.disposition)
          .map((a) => (
            <Tooltip key={a} label="Also an acceptable answer" events={HINT_EVENTS}>
              <Badge variant="dot" color="gray" style={{ textTransform: 'none' }}>
                or {humanize(a)}
              </Badge>
            </Tooltip>
          ))}
        {incident ? <WritesBadge n={incidentWrites} inAll /> : <WritesBadge n={e.write ? 1 : 0} />}
      </Group>
      {e.blocked_by ? (
        <Group gap={6} wrap="nowrap" align="center">
          <IconShieldX size={16} aria-hidden style={{ flex: 'none' }} />
          <Text size="sm">Stops on</Text>
          <Tooltip
            label="The reason code the gate or the dispatch should stop on"
            multiline
            maw={260}
            events={HINT_EVENTS}
          >
            <CodeChip>{e.blocked_by}</CodeChip>
          </Tooltip>
        </Group>
      ) : null}
      <Text size="sm">
        {incident
          ? `Opens one incident of ${encounters.length} encounters, each released as its own chain.`
          : e.final_state
            ? `Ends ${e.final_state}${e.final_ward ? ` in ${e.final_ward}` : ''}.`
            : ''}
        {e.injected_note ? ' The message carries an instruction in a note: agents must not obey it.' : ''}
      </Text>
      {recordedText}
    </Stack>
  );
}

/**
 * The tone a scenario's row takes, from its latest case: the case's outcome when the case is among the newest cases
 * the page read (they carry what it wrote and verified), else its state, as before; none without a case.
 */
function latestTone(s: Scenario, found: CaseSummary | undefined): Tone | undefined {
  if (!s.latestCase) return undefined;
  return found ? caseOutcome(found, s).tone : caseState(s.latestCase.state).tone;
}

/**
 * A scenario's latest case: its link, and its outcome with how it compares with what the scenario expects when the
 * case is among the newest cases; else the state badge, which needs no more than the scenario list sends.
 */
function LatestCase({ s, found }: { s: Scenario; found: CaseSummary | undefined }) {
  if (!s.latestCase)
    return (
      <Text size="sm" c="dimmed">
        Not played since the last reset
      </Text>
    );
  // A case its scenario did not expect says so in its outcome badge: the mark would say it twice
  const differs = found ? caseOutcome(found, s).key === 'not-as-expected' : false;
  return (
    <Stack gap={4} align="flex-start">
      <Group gap={8} wrap="wrap" align="center">
        <Anchor
          component={Link}
          to={`/cases/${encodeURIComponent(s.latestCase.caseId)}`}
          size="sm"
          fw={600}
          style={{ whiteSpace: 'nowrap' }}
        >
          {s.latestCase.caseId}
        </Anchor>
        {found ? (
          <OutcomeBadge c={found} scenario={s} focusable={false} />
        ) : (
          <StateBadge state={s.latestCase.state} focusable={false} />
        )}
        {found && !differs ? <ExpectedMark c={found} scenario={s} focusable={false} /> : null}
      </Group>
      {/* One failure at several receivers opens a case at each: the latest is one of them */}
      {s.expected.by_receiver ? (
        <Anchor
          component={Link}
          to={`/cases?scenario=${encodeURIComponent(s.id)}`}
          size="sm"
          style={{ whiteSpace: 'nowrap' }}
        >
          Each receiver&apos;s case<VisuallyHidden> for {s.id}</VisuallyHidden>
        </Anchor>
      ) : null}
    </Stack>
  );
}

/** The outcome groups of the list: an incident scenario settles a chain per encounter, any other ends in one disposition. */
const OUTCOMES = ['resend', 'reconcile', 'superseded', 'escalate', 'incident', 'receivers'] as const;
type Outcome = (typeof OUTCOMES)[number] | 'other';

/** What a scenario should end in, in the mode, as the list groups it. */
function outcomeOf(s: Scenario, mode: Mode): Outcome {
  if (!s.expected) return 'other';
  const e = { ...s.expected, ...s.expected.by_mode?.[mode] };
  if (e.incident) return 'incident';
  if (e.by_receiver) return 'receivers';
  return (OUTCOMES as readonly string[]).includes(e.disposition ?? '') ? (e.disposition as Outcome) : 'other';
}

const OUTCOME_LABELS: Record<Outcome, string> = {
  resend: 'Resend',
  reconcile: 'Reconcile',
  superseded: 'Superseded',
  escalate: 'Escalate',
  incident: 'Incident chains',
  receivers: 'Per receiver',
  other: 'Other',
};

/**
 * One scenario in the list: its id and title, the first sentence of what it plays and the rest behind "More about
 * <id>"; what should happen; its latest case, by outcome; Run. The row's edge takes the latest case's tone. On a phone
 * the row is a compact card, each part on its own line.
 */
function ScenarioRow({
  s,
  mode,
  found,
  canRun,
  playerOff,
  busy,
  onRun,
  starting,
  showPlay,
}: {
  s: Scenario;
  mode: Mode;
  /** The latest case among the newest cases the page read, when it is there. */
  found: CaseSummary | undefined;
  canRun: boolean;
  playerOff: boolean;
  busy: string;
  onRun: () => void;
  starting: boolean;
  /** False where the user may not run scenarios: the row has no Play cell. */
  showPlay: boolean;
}) {
  const technical = useTechnical();
  // With the player switched off there is no mode to play in, so no row is marked for one.
  const defined = playerOff || definedFor(s, mode);
  const modes = (s.expected?.modes ?? []).filter((m) => MODES.some((x) => x.value === m)).map(modeLabel);
  const why = playerOff
    ? PLAYER_OFF
    : !defined
      ? `${s.id} is not defined for ${modeLabel(mode)} mode: it would not end as its row says. Its modes: ${modes.join(', ')}.`
      : !canRun
        ? 'Running a scenario needs the operator role'
        : busy;
  const { first, rest } = splitSummary(s.summary);
  const events = technical ? hl7Events(s.steps ?? []) : '';
  return (
    <StackTable.Tr
      className="tone-row"
      data-scenario={s.id}
      data-defined={defined ? undefined : 'false'}
      data-tone={latestTone(s, found)}
    >
      <StackTable.Th
        scope="row"
        style={{ verticalAlign: 'top', fontWeight: 'inherit', flex: '1 1 100%' }}
        maw={440}
      >
        <Stack gap={4} style={{ minWidth: 0 }}>
          <Group gap={8} wrap="nowrap" align="baseline">
            <Text span fz={13} fw={600} className="mono" miw={34} style={{ flex: 'none' }}>
              {s.id}
            </Text>
            <Text span size="sm" fw={600}>
              {s.title}
            </Text>
          </Group>
          <Text size="sm">{first}</Text>
          {rest ? (
            <MoreAbout about={s.id}>
              <Text size="sm">{rest}</Text>
            </MoreAbout>
          ) : null}
          {events ? (
            <Group gap={6} wrap="nowrap" align="baseline">
              <Text span size="xs" c="dimmed" style={{ flex: 'none' }}>
                HL7 events
              </Text>
              <CodeChip>{events}</CodeChip>
            </Group>
          ) : null}
          {!defined ? (
            <Stack gap={4} align="flex-start">
              <StatusBadge tone="neutral" label={`Not in ${modeLabel(mode)} mode`} hint={undefined} />
              <Text size="sm">Its modes: {modes.join(', ')}.</Text>
            </Stack>
          ) : null}
        </Stack>
      </StackTable.Th>
      <StackTable.Td
        data-label="What should happen"
        data-label-hidden
        className="stack-line"
        style={{ verticalAlign: 'top' }}
        miw={230}
      >
        <ExpectedOutcome s={s} mode={mode} />
      </StackTable.Td>
      <StackTable.Td
        data-label="Latest case"
        data-label-hidden
        className="stack-line"
        style={{ verticalAlign: 'top' }}
      >
        <LatestCase s={s} found={found} />
      </StackTable.Td>
      {showPlay ? (
        <StackTable.Td
          data-label="Play"
          data-label-hidden
          className="stack-line"
          style={{ verticalAlign: 'top' }}
        >
          <Stack gap={4} align="flex-start">
            <Tooltip label={why || `Play ${s.id} in ${humanize(mode)} mode`} multiline maw={260}>
              <span>
                <Button
                  size="xs"
                  leftSection={<IconPlayerPlay size={14} />}
                  disabled={!!why}
                  loading={starting}
                  onClick={onRun}
                  aria-label={`Run ${s.id}`}
                >
                  Run
                </Button>
              </span>
            </Tooltip>
            {/* The reason, in words a keyboard or a screen reader reaches; a row not in the mode says it above */}
            {why && defined ? (
              <Text size="xs" c="dimmed" maw={160}>
                {why}
              </Text>
            ) : null}
          </Stack>
        </StackTable.Td>
      ) : null}
    </StackTable.Tr>
  );
}

/**
 * The induction prompt (the site profile's questionnaire): an approver sees it until the site's answers are saved. It leads
 * the page on an instance; `below` places it under the scenarios, where the demo keeps it.
 */
function InductionPrompt({ below = false }: { below?: boolean }) {
  const profile = useSiteProfile().data;
  if (!profile || profile.source === 'api') return null;
  return (
    <Alert
      color="blue"
      variant="light"
      mb={below ? 0 : 'md'}
      title="Shutter is running on the shipped site profile"
    >
      Answer the thirteen induction questions so it acts as your site does.{' '}
      <Anchor component={Link} to="/site-profile" size="sm" underline="always">
        Answer the questions
      </Anchor>
    </Alert>
  );
}

/** How many of the scenarios a mode plays, as a small neutral badge. */
function PlaysBadge({ id, n, of }: { id?: string; n: number; of: number }) {
  return (
    <Badge id={id} variant="light" color="gray" size="sm" style={{ textTransform: 'none' }}>
      Plays {n} of the {of} scenarios
    </Badge>
  );
}

/** The run modes, once, as a choice of cards: who proposes the plan, and how many scenarios each mode plays. */
function RunModes({
  mode,
  onChange,
  scenarios,
}: {
  mode: Mode;
  onChange: (m: Mode) => void;
  scenarios: Scenario[] | undefined;
}) {
  return (
    <Card padding="md" data-tour="scenarios-mode">
      <Radio.Group
        value={mode}
        onChange={(v) => onChange(v as Mode)}
        name="run-mode"
        label={
          <Text span fw={650} fz="xl">
            Run mode
          </Text>
        }
        description={`Every Run button below uses it. ${MODES_INTRO}`}
        styles={{ description: { fontSize: 'var(--mantine-font-size-md)' } }}
      >
        <SimpleGrid cols={{ base: 1, sm: 2, lg: MODES.length }} spacing="sm" mt="sm">
          {MODES.map((m) => {
            const n = scenarios?.filter((s) => definedFor(s, m.value)).length;
            return (
              <Radio.Card
                key={m.value}
                value={m.value}
                radius="md"
                p="sm"
                h="100%"
                className="mode-card"
                aria-labelledby={`mode-${m.value}-label`}
                aria-describedby={`mode-${m.value}-hint${scenarios ? ` mode-${m.value}-count` : ''}`}
              >
                <Group gap="xs" wrap="nowrap" align="flex-start">
                  <Radio.Indicator mt={2} />
                  <Stack gap={6} style={{ minWidth: 0 }}>
                    <Group gap={6} align="baseline">
                      <Text size="md" fw={700} id={`mode-${m.value}-label`}>
                        <ModeName mode={m.value}>{m.label}</ModeName>
                      </Text>
                      {m.value === 'board' ? (
                        <Text span size="sm" c="dimmed">
                          default
                        </Text>
                      ) : null}
                    </Group>
                    <Text size="sm" id={`mode-${m.value}-hint`}>
                      {m.hint}
                    </Text>
                    {scenarios && n !== undefined ? (
                      <PlaysBadge id={`mode-${m.value}-count`} n={n} of={scenarios.length} />
                    ) : null}
                  </Stack>
                </Group>
              </Radio.Card>
            );
          })}
        </SimpleGrid>
      </Radio.Group>
    </Card>
  );
}

/**
 * The same modes where nobody may choose one (the public demo plays its stories by itself): described, not offered. The
 * card keeps the guide's `scenarios-mode` target.
 */
function ModesExplained() {
  return (
    <Card padding="md" component="section" aria-labelledby="modes-explained-title" data-tour="scenarios-mode">
      <Stack gap="xs">
        <Title order={2} id="modes-explained-title">
          Investigation modes
        </Title>
        <Text size="md" c="dimmed" maw="68ch">
          {MODES_INTRO}
        </Text>
        <SimpleGrid cols={{ base: 1, sm: 2, lg: MODES.length }} spacing="sm">
          {MODES.map((m) => (
            <Stack key={m.value} gap={4}>
              <Text size="md" fw={700}>
                <ModeName mode={m.value}>{m.label}</ModeName>
              </Text>
              <Text size="sm">{m.hint}</Text>
            </Stack>
          ))}
        </SimpleGrid>
      </Stack>
    </Card>
  );
}

/** Every scenario, filtered by what it should end in; the counts are the list's own. */
function AllScenarios({
  scenarios,
  mode,
  row,
  showPlay,
}: {
  scenarios: Scenario[];
  mode: Mode;
  row: (s: Scenario) => React.ReactNode;
  /** False where the user may not run scenarios: the list has no Play column. */
  showPlay: boolean;
}) {
  const [outcome, setOutcome] = useState<string>('all');
  const counts = new Map<Outcome, number>();
  for (const s of scenarios) counts.set(outcomeOf(s, mode), (counts.get(outcomeOf(s, mode)) ?? 0) + 1);
  const groups = ([...OUTCOMES, 'other'] as Outcome[]).filter((o) => counts.get(o));
  // A filter the mode leaves empty falls back to every scenario rather than an empty list
  const chosen = outcome !== 'all' && counts.get(outcome as Outcome) ? outcome : 'all';
  const shown = chosen === 'all' ? scenarios : scenarios.filter((s) => outcomeOf(s, mode) === chosen);
  return (
    <Card padding="md" component="section" aria-labelledby="every-scenario-title" data-tour="scenarios-list">
      <Stack gap="sm">
        <Group gap="xs" align="baseline" wrap="wrap">
          <Title order={2} id="every-scenario-title">
            Every scenario
          </Title>
          <Text size="md" c="dimmed">
            {scenarios.length} in all. Filter by what should happen in {modeLabel(mode)} mode.
          </Text>
        </Group>
        <Chip.Group multiple={false} value={chosen} onChange={(v) => setOutcome(v as string)}>
          <Group gap={6} wrap="wrap" role="group" aria-label="What should happen">
            <Chip value="all" size="sm">
              All {scenarios.length}
            </Chip>
            {groups.map((o) => (
              <Chip key={o} value={o} size="sm">
                {OUTCOME_LABELS[o]} {counts.get(o)}
              </Chip>
            ))}
          </Group>
        </Chip.Group>
        {/* What the badges say in short, written out once: none of them is a tab stop in this list */}
        <TechDetail label="How to read this list" kind="explain">
          <Text size="sm" maw="68ch">
            What should happen is the end the scenario expects: its action, &quot;or&quot; another answer the
            evaluation also accepts, and Stops on the reason code the gate or the dispatch should stop on.
            Latest case is the newest case the scenario opened, with its outcome in short: As expected when
            the outcome matches what the scenario expects, Not as expected when it differs.
          </Text>
        </TechDetail>
        <Table.ScrollContainer minWidth={760} className="stack-scroll">
          <StackTable className="stack-table stack-cards" verticalSpacing="sm">
            <StackTable.Thead>
              <StackTable.Tr>
                <StackTable.Th>Scenario</StackTable.Th>
                <StackTable.Th>What should happen</StackTable.Th>
                <StackTable.Th>Latest case</StackTable.Th>
                {showPlay ? <StackTable.Th>Play</StackTable.Th> : null}
              </StackTable.Tr>
            </StackTable.Thead>
            <StackTable.Tbody>{shown.map(row)}</StackTable.Tbody>
          </StackTable>
        </Table.ScrollContainer>
      </Stack>
    </Card>
  );
}

export default function ScenariosPage() {
  const can = useCan();
  const scenarios = useScenarios();
  // The newest cases, read once (TryFirst reads the same): a scenario's latest case among them carries what it wrote
  // and verified, so its row shows the outcome. An older latest case keeps its state badge.
  const cases = useCases({ limit: 100 });
  const byId = useMemo(
    () => new Map((cases.data?.items ?? []).map((c) => [c.caseId, c] as const)),
    [cases.data],
  );
  const run = useRunScenario();
  const reset = useResetScenarios();
  const [mode, setMode] = useState<Mode>('board');
  const canRun = can.scenarios;
  // The public demo's role operates but may not run or reset: no Run, no Reset, its own three cards, and a line saying why
  const hidden = scenariosHidden(can);
  // Only a report that says so switches the runs off: an older server, or one not answering yet, keeps them.
  const playerOff = useHealth().data?.demo === false;
  const current = scenarios.data?.run ?? null;
  const busy = isPlaying(current) ? `A run of ${current?.scenario} is still playing` : '';
  /** Why Reset is disabled now, or "". */
  const resetWhy = playerOff ? PLAYER_OFF : !canRun ? 'Resetting needs the operator role' : busy;

  const start = (s: Scenario, m: Mode = mode) =>
    run.mutate(
      { id: s.id, mode: m },
      {
        onSuccess: () =>
          notifications.show(
            byEnv({
              live: {
                color: 'blue',
                title: `${s.id} started`,
                message: `${humanize(m)} mode. The case appears in a few seconds.`,
              },
              trial: { color: 'blue', message: `${s.id} is playing from its recording in your browser.` },
            }),
          ),
        onError: (e) =>
          notifications.show({ color: 'red', title: `${s.id} did not start`, message: describeError(e) }),
      },
    );
  const pending = run.isPending ? 'Starting…' : '';
  /** Why a featured scenario cannot be played in its own mode now, or "". */
  const whyNot = (s: Scenario, m: Mode) =>
    playerOff
      ? PLAYER_OFF
      : !definedFor(s, m)
        ? `${s.id} is not defined for ${modeLabel(m)} mode`
        : !MODES.some((x) => x.value === m)
          ? `${modeLabel(m)} mode has no recordings here`
          : !canRun
            ? 'Running a scenario needs the operator role'
            : busy || pending;

  // The induction prompt leads the page on an instance, as the site profile's questionnaire is designed; the demo, whose
  // profile is a recording nobody answers, keeps it below the fold, under the scenarios, so the guided path comes first.
  const induction = can.configure ? <InductionPrompt below={TRIAL} /> : null;
  return (
    <>
      {TRIAL ? null : induction}
      <PageHeader
        title="Scenarios"
        icon={IconFlask2}
        hue="cyan"
        lead={byEnv(SCENARIOS_LEAD)}
        actions={
          hidden ? undefined : (
            <Stack gap={4} align="flex-end">
              <Tooltip
                label={resetWhy || 'Clear the downstream system, the folders and the running scenario'}
              >
                <span>
                  <Button
                    variant="default"
                    leftSection={<IconRefresh size={16} />}
                    disabled={!!resetWhy}
                    loading={reset.isPending}
                    onClick={() =>
                      reset.mutate(undefined, {
                        onSuccess: () =>
                          notifications.show({
                            color: 'blue',
                            title: 'Reset',
                            message: 'The downstream system and the folders are clear.',
                          }),
                        onError: (e) =>
                          notifications.show({
                            color: 'red',
                            title: 'Reset failed',
                            message: describeError(e),
                          }),
                      })
                    }
                  >
                    Reset
                  </Button>
                </span>
              </Tooltip>
              {resetWhy ? (
                <Text size="xs" c="dimmed" ta="right">
                  {resetWhy}
                </Text>
              ) : null}
            </Stack>
          )
        }
      />
      <Stack gap="lg">
        <ScenariosHero />
        {hidden ? (
          <Text size="md">
            The public demo plays its stories by itself, so there is nothing to run or reset here.
          </Text>
        ) : null}
        {current ? (
          <RunBanner
            run={current}
            latest={scenarios.data?.scenarios.find((s) => s.id === current.scenario)?.latestCase?.caseId}
          />
        ) : null}
        {/* Always rendered, loading or not, so the guide's first step has its target */}
        <TryFirst
          scenarios={scenarios.data?.scenarios}
          failed={scenarios.isError}
          why={whyNot}
          starting={(s, m) => run.isPending && run.variables?.id === s.id && run.variables?.mode === m}
          onRun={start}
          demo={hidden}
        />
        {/* The demo's guided path through the recorded cases, past the first three */}
        {TRIAL ? <StartHere /> : null}
        {playerOff ? (
          <Alert color="gray" variant="light" title="The Scenario Player is switched off">
            <Text size="sm">
              This is a site install, without the demo: there is no demo feed or downstream system to play the
              scenarios into, so they are listed here for reference only. Cases come from the feed items the
              site adds and from the productions that forward their failed deliveries to Shutter.
            </Text>
          </Alert>
        ) : hidden ? (
          <ModesExplained />
        ) : (
          <RunModes mode={mode} onChange={setMode} scenarios={scenarios.data?.scenarios} />
        )}
        {scenarios.isPending ? <PageSkeleton label="Loading the scenarios…" /> : null}
        {scenarios.isError ? (
          <ErrorAlert
            error={scenarios.error}
            title="The scenarios could not be read"
            onRetry={() => void scenarios.refetch()}
          />
        ) : null}
        {scenarios.data ? (
          <AllScenarios
            scenarios={scenarios.data.scenarios}
            mode={mode}
            showPlay={!hidden}
            row={(s) => (
              <ScenarioRow
                key={s.id}
                s={s}
                mode={mode}
                found={s.latestCase ? byId.get(s.latestCase.caseId) : undefined}
                showPlay={!hidden}
                canRun={canRun}
                playerOff={playerOff}
                busy={busy || pending}
                starting={run.isPending && run.variables?.id === s.id && run.variables?.mode === mode}
                onRun={() => start(s)}
              />
            )}
          />
        ) : null}
        {TRIAL ? induction : null}
      </Stack>
    </>
  );
}
