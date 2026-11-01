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
  Spoiler,
  Stack,
  Table,
  Text,
  Title,
  Tooltip,
  VisuallyHidden,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconPlayerPlay, IconRefresh, IconShieldX } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import {
  isPlaying,
  useCan,
  useHealth,
  useResetScenarios,
  useRunScenario,
  useScenarios,
  useSiteProfile,
} from '@/api/hooks';
import { scenariosHidden } from '@/api/can';
import type { Mode, Scenario, ScenarioRun } from '@/api/types';
import { DEMO } from '@/demo';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { StackTable } from '@/components/StackTable';
import { proposedWrites, writes } from '@/lib/status';
import { describeError } from '@/lib/errors';
import { formatAge, humanize } from '@/lib/format';
import { StartHere } from './StartHere';
import { ScenariosHero, TryFirst } from './TryFirst';

const ALL_MODES: { value: Mode; label: string; hint: string }[] = [
  {
    value: 'board',
    label: 'Board',
    hint: 'Three specialists review the evidence in parallel; a coordinator proposes one plan',
  },
  {
    value: 'policy',
    label: 'Site policy',
    hint: "The scenario catalogue and the site's profile settle the cases they know, still gated, rehearsed and verified; the rest go to the board",
  },
  {
    value: 'single',
    label: 'Single investigator',
    hint: 'One generalist agent looks at everything and proposes the plan',
  },
  {
    value: 'rules',
    label: 'Rules only',
    hint: 'No agents: resend unchanged unless the gate objects. The baseline to compare with',
  },
];

/** The demo leaves out the single investigator: its runs were never recorded, so it has nothing to replay. */
const MODES = DEMO ? ALL_MODES.filter((m) => m.value !== 'single') : ALL_MODES;

const modeLabel = (mode: Mode) => ALL_MODES.find((m) => m.value === mode)?.label ?? humanize(mode);

/** Whether the scenario is defined for the mode: one that names its modes isn't for the others. */
const definedFor = (s: Scenario, mode: Mode) => !s.expected?.modes || s.expected.modes.includes(mode);

/** Why nothing can be played on a site install: the server switches the Scenario Player off (CONTRACTS 12). */
const PLAYER_OFF = 'The Scenario Player is switched off on a site install, which has no demo';

function RunBanner({ run }: { run: ScenarioRun }) {
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
          {run.timeouts.length ? ` The case did not reach ${run.timeouts.join(', ')} in time.` : ''} The
          production does the rest: follow the case below.
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

/** What should happen in the mode: the scenario's expected outcome with the mode's own additions (expected.by_mode). */
function ExpectedOutcome({ s, mode }: { s: Scenario; mode: Mode }) {
  if (!s.expected) return null;
  const e = { ...s.expected, ...s.expected.by_mode?.[mode] };
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
            <Text size="xs" fw={600}>
              {receiver}
            </Text>
            <DispositionBadge disposition={x.disposition} />
            {x.write ? (
              <StatusBadge {...proposedWrites(1)} label="One conditional write" hint={undefined} />
            ) : (
              <StatusBadge {...writes(0)} label="Nothing written" hint={undefined} />
            )}
            {x.outcome === 'correct_history' ? (
              <Text size="xs" c="dimmed">
                with the steps that correct its history
              </Text>
            ) : null}
          </Group>
        ))}
        <Text size="xs" c="dimmed">
          One case per receiver.{' '}
          {e.final_state ? `Each ends ${e.final_state}${e.final_ward ? ` in ${e.final_ward}` : ''}.` : ''}
        </Text>
      </Stack>
    );
  }
  return (
    <Stack gap={4}>
      <Group gap={6}>
        <DispositionBadge disposition={e.disposition ?? ''} />
        {e.acceptable
          ?.filter((a) => a !== e.disposition)
          .map((a) => (
            <Tooltip key={a} label="Also an acceptable answer">
              <Badge variant="dot" color="gray" style={{ textTransform: 'none' }} tabIndex={0}>
                or {humanize(a)}
              </Badge>
            </Tooltip>
          ))}
        {incident ? (
          <StatusBadge
            {...proposedWrites(incidentWrites)}
            label={`${incidentWrites} conditional write${incidentWrites === 1 ? '' : 's'} in all`}
            hint={undefined}
          />
        ) : e.write ? (
          <StatusBadge {...proposedWrites(1)} label="One conditional write" hint={undefined} />
        ) : (
          <StatusBadge {...writes(0)} label="Nothing written" hint={undefined} />
        )}
        {e.blocked_by ? (
          <StatusBadge
            tone="blocking"
            label={e.blocked_by}
            hint="The reason code the gate or the dispatch should stop on"
            icon={IconShieldX}
          />
        ) : null}
      </Group>
      <Text size="xs" c="dimmed">
        {incident
          ? `Opens one incident of ${encounters.length} encounters, each released as its own chain.`
          : e.final_state
            ? `Ends ${e.final_state}${e.final_ward ? ` in ${e.final_ward}` : ''}.`
            : ''}
        {e.injected_note ? ' The message carries an instruction in a note: agents must not obey it.' : ''}
      </Text>
    </Stack>
  );
}

/** The list's outcome groups: an incident scenario settles a chain per encounter, any other ends in one disposition. */
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

/** One scenario in the list: its id, title and what it plays; what should happen; its latest case; Run. */
function ScenarioRow({
  s,
  mode,
  canRun,
  playerOff,
  busy,
  onRun,
  starting,
  showPlay,
}: {
  s: Scenario;
  mode: Mode;
  canRun: boolean;
  playerOff: boolean;
  busy: string;
  onRun: () => void;
  starting: boolean;
  /** False where the user may not run scenarios: the row has no Play cell. */
  showPlay: boolean;
}) {
  // With the player switched off there is no mode to play in, so no row is greyed out for one.
  const defined = playerOff || definedFor(s, mode);
  const modes = (s.expected?.modes ?? []).filter((m) => MODES.some((x) => x.value === m)).map(modeLabel);
  const why = playerOff
    ? PLAYER_OFF
    : !defined
      ? `${s.id} is not defined for ${modeLabel(mode)} mode: it would not end as its row says. Its modes: ${modes.join(', ')}.`
      : !canRun
        ? 'Running a scenario needs the operator role'
        : busy;
  return (
    <StackTable.Tr
      data-scenario={s.id}
      data-defined={defined ? undefined : 'false'}
      bg={defined ? undefined : 'var(--mantine-color-default-hover)'}
    >
      <StackTable.Th scope="row" style={{ verticalAlign: 'top', fontWeight: 'inherit' }} maw={420}>
        <Group gap={8} wrap="nowrap" align="baseline">
          <Text size="sm" fw={700} miw={30}>
            {s.id}
          </Text>
          <Stack gap={2} style={{ minWidth: 0 }}>
            <Text size="sm" fw={600}>
              {s.title}
            </Text>
            {/* The whole scenario stays a click away; two lines keep the list scannable */}
            <Spoiler
              maxHeight={38}
              showLabel={
                <Text span size="xs">
                  More<VisuallyHidden> about {s.id}</VisuallyHidden>
                </Text>
              }
              hideLabel={
                <Text span size="xs">
                  Less<VisuallyHidden> about {s.id}</VisuallyHidden>
                </Text>
              }
              fz="xs"
            >
              <Text size="xs" c="dimmed">
                {s.summary}
              </Text>
            </Spoiler>
            {!defined ? (
              <Text size="xs" fw={600}>
                Not defined for {modeLabel(mode)} mode. Its modes: {modes.join(', ')}.
              </Text>
            ) : null}
          </Stack>
        </Group>
      </StackTable.Th>
      <StackTable.Td data-label="What should happen" style={{ verticalAlign: 'top' }} miw={220}>
        <ExpectedOutcome s={s} mode={mode} />
      </StackTable.Td>
      <StackTable.Td data-label="Latest case" style={{ verticalAlign: 'top' }}>
        {s.latestCase ? (
          <Stack gap={4} align="flex-start">
            <Anchor
              component={Link}
              to={`/cases/${encodeURIComponent(s.latestCase.caseId)}`}
              size="sm"
              fw={600}
              style={{ whiteSpace: 'nowrap' }}
            >
              {s.latestCase.caseId}
            </Anchor>
            <StateBadge state={s.latestCase.state} size="xs" />
            {/* One failure at several receivers opens a case at each: the latest is one of them */}
            {s.expected.by_receiver ? (
              <Anchor
                component={Link}
                to={`/cases?scenario=${encodeURIComponent(s.id)}`}
                size="xs"
                style={{ whiteSpace: 'nowrap' }}
              >
                Each receiver&apos;s case<VisuallyHidden> for {s.id}</VisuallyHidden>
              </Anchor>
            ) : null}
          </Stack>
        ) : (
          <Text size="xs" c="dimmed">
            Not played since the last reset
          </Text>
        )}
      </StackTable.Td>
      {showPlay ? (
        <StackTable.Td data-label="Play" style={{ verticalAlign: 'top' }}>
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
        </StackTable.Td>
      ) : null}
    </StackTable.Tr>
  );
}

/**
 * The induction prompt (the owner's questionnaire): an approver sees it until the site's answers are saved. It leads
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
      Answer the twelve induction questions so it acts as your site does.{' '}
      <Anchor component={Link} to="/site-profile" size="sm" underline="always">
        Answer the questions
      </Anchor>
    </Alert>
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
          <Text span fw={600} size="md">
            Run mode
          </Text>
        }
        description="Chosen once here, used by every Run button in the list. The mode chooses who proposes the plan. The gate, the rehearsal and the release, by a person, or the site's written policy, are the same in every mode."
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
                className="mode-card"
                aria-labelledby={`mode-${m.value}-label`}
                aria-describedby={`mode-${m.value}-hint`}
              >
                <Group gap="xs" wrap="nowrap" align="flex-start">
                  <Radio.Indicator mt={2} />
                  <Stack gap={2} style={{ minWidth: 0 }}>
                    <Group gap={6} align="baseline">
                      <Text size="sm" fw={700} id={`mode-${m.value}-label`}>
                        {m.label}
                      </Text>
                      {m.value === 'board' ? (
                        <Text span size="xs" c="dimmed">
                          default
                        </Text>
                      ) : null}
                    </Group>
                    <Text size="sm" id={`mode-${m.value}-hint`}>
                      {m.hint}.{scenarios ? ` Plays ${n} of the ${scenarios.length} scenarios.` : ''}
                    </Text>
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
        <Title order={2} fz="md" id="modes-explained-title">
          Investigation modes
        </Title>
        <Text size="sm" c="dimmed">
          The mode chooses who proposes the plan. The gate, the rehearsal and the release, by a person, or the
          site&apos;s written policy, are the same in every mode.
        </Text>
        <SimpleGrid cols={{ base: 1, sm: 2, lg: MODES.length }} spacing="sm">
          {MODES.map((m) => (
            <Stack key={m.value} gap={2}>
              <Text size="sm" fw={700}>
                {m.label}
              </Text>
              <Text size="sm">{m.hint}.</Text>
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
          <Title order={2} fz="lg" id="every-scenario-title">
            Every scenario
          </Title>
          <Text size="sm" c="dimmed">
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
        <Table.ScrollContainer minWidth={760} className="stack-scroll">
          <StackTable className="stack-table" verticalSpacing="sm">
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
  const run = useRunScenario();
  const reset = useResetScenarios();
  const [mode, setMode] = useState<Mode>('board');
  const canRun = can.scenarios;
  // The public demo's role operates but may not run or reset: no Run, no Reset, and a line saying why
  const hidden = scenariosHidden(can);
  // Only a report that says so switches the runs off: an older server, or one not answering yet, keeps them.
  const playerOff = useHealth().data?.demo === false;
  const current = scenarios.data?.run ?? null;
  const busy = isPlaying(current) ? `A run of ${current?.scenario} is still playing` : '';

  const start = (s: Scenario, m: Mode = mode) =>
    run.mutate(
      { id: s.id, mode: m },
      {
        onSuccess: () =>
          notifications.show({
            color: 'blue',
            title: `${s.id} started`,
            message: `${humanize(m)} mode. The case appears in a few seconds.`,
          }),
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

  // The induction prompt leads the page on an instance, as the owner's questionnaire is designed; the demo, whose
  // profile is a recording nobody answers, keeps it below the fold, under the scenarios, so the guided path comes first.
  const induction = can.configure ? <InductionPrompt below={DEMO} /> : null;
  return (
    <>
      {DEMO ? null : induction}
      <PageHeader
        title="Scenarios"
        actions={
          hidden ? undefined : (
            <Tooltip
              label={
                playerOff
                  ? PLAYER_OFF
                  : !canRun
                    ? 'Resetting needs the operator role'
                    : busy || 'Clear the downstream system, the folders and the running scenario'
              }
            >
              <span>
                <Button
                  variant="default"
                  leftSection={<IconRefresh size={16} />}
                  disabled={playerOff || !canRun || !!busy}
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
          )
        }
      />
      <Stack gap="md">
        <ScenariosHero />
        {hidden ? (
          <Text size="sm">
            The public demo plays its stories by itself, so there is nothing to run or reset here.
          </Text>
        ) : null}
        {current ? <RunBanner run={current} /> : null}
        {/* Always rendered, loading or not, so the guide's first step has its target */}
        <TryFirst
          scenarios={scenarios.data?.scenarios}
          failed={scenarios.isError}
          why={whyNot}
          starting={(s, m) => run.isPending && run.variables?.id === s.id && run.variables?.mode === m}
          onRun={start}
          runnable={!hidden}
        />
        {/* The demo's guided path through the recorded cases, past the first three */}
        {DEMO ? <StartHere /> : null}
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
        {DEMO ? induction : null}
      </Stack>
    </>
  );
}
