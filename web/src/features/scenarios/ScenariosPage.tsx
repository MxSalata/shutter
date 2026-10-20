import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  Loader,
  SegmentedControl,
  SimpleGrid,
  Stack,
  Text,
  Title,
  Tooltip,
  VisuallyHidden,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconPlayerPlay, IconRefresh } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import {
  isPlaying,
  useHealth,
  useMe,
  useResetScenarios,
  useRunScenario,
  useScenarios,
  useSiteProfile,
} from '@/api/hooks';
import type { Mode, Scenario, ScenarioRun } from '@/api/types';
import { DEMO } from '@/demo';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { describeError } from '@/lib/errors';
import { formatAge, humanize } from '@/lib/format';
import { StartHere } from './StartHere';

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
        color="teal"
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

function ExpectedOutcome({ s }: { s: Scenario }) {
  const e = s.expected;
  if (!e) return null;
  return (
    <Stack gap={4}>
      <Text size="xs" fw={600} c="dimmed" tt="uppercase">
        What should happen
      </Text>
      <Group gap={6}>
        <DispositionBadge disposition={e.disposition} />
        {e.acceptable
          ?.filter((a) => a !== e.disposition)
          .map((a) => (
            <Tooltip key={a} label="Also an acceptable answer">
              <Badge variant="dot" color="gray" style={{ textTransform: 'none' }} tabIndex={0}>
                or {humanize(a)}
              </Badge>
            </Tooltip>
          ))}
        <Badge variant="light" color={e.write ? 'indigo' : 'gray'} style={{ textTransform: 'none' }}>
          {e.write ? 'One conditional write' : 'Nothing written'}
        </Badge>
        {e.blocked_by ? (
          <Tooltip label="The reason code the gate or the dispatch should stop on">
            <Badge variant="light" color="red" style={{ textTransform: 'none' }} tabIndex={0}>
              {e.blocked_by}
            </Badge>
          </Tooltip>
        ) : null}
      </Group>
      <Text size="xs" c="dimmed">
        Ends {e.final_state}
        {e.final_ward ? ` in ${e.final_ward}` : ''}.
        {e.injected_note ? ' The message carries an instruction in a note: agents must not obey it.' : ''}
      </Text>
    </Stack>
  );
}

function ScenarioCard({
  s,
  mode,
  canRun,
  playerOff,
  busy,
  onRun,
  starting,
}: {
  s: Scenario;
  mode: Mode;
  canRun: boolean;
  playerOff: boolean;
  busy: string;
  onRun: () => void;
  starting: boolean;
}) {
  // With the player switched off there is no mode to play in, so no card is greyed out for one.
  const defined = playerOff || definedFor(s, mode);
  const modes = (s.expected?.modes ?? []).filter((m) => MODES.some((x) => x.value === m)).map(modeLabel);
  const why = playerOff
    ? PLAYER_OFF
    : !defined
      ? `${s.id} is not defined for ${modeLabel(mode)} mode: it would not end as its card says. Its modes: ${modes.join(', ')}.`
      : !canRun
        ? 'Running a scenario needs the operator role'
        : busy;
  return (
    <Card
      padding="md"
      bg={defined ? undefined : 'var(--mantine-color-default-hover)'}
      data-defined={defined ? undefined : 'false'}
    >
      <Stack gap="sm" h="100%">
        <Group justify="space-between" wrap="nowrap" align="flex-start">
          <Stack gap={2} style={{ minWidth: 0 }}>
            <Text size="xs" c="dimmed" fw={600}>
              {s.id}
            </Text>
            <Title order={3} fz="md">
              {s.title}
            </Title>
          </Stack>
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
        </Group>
        <Text size="sm">{s.summary}</Text>
        {!defined ? (
          <Text size="xs" fw={600}>
            Not defined for {modeLabel(mode)} mode. Its modes: {modes.join(', ')}.
          </Text>
        ) : null}
        <ExpectedOutcome s={s} />
        <div style={{ flex: 1 }} />
        {s.latestCase ? (
          <Group gap={6} wrap="nowrap">
            <Text size="xs" c="dimmed">
              Latest case
            </Text>
            <Anchor
              component={Link}
              to={`/cases/${encodeURIComponent(s.latestCase.caseId)}`}
              size="sm"
              fw={600}
            >
              {s.latestCase.caseId}
            </Anchor>
            <StateBadge state={s.latestCase.state} size="xs" />
          </Group>
        ) : (
          <Text size="xs" c="dimmed">
            Not played since the last reset
          </Text>
        )}
      </Stack>
    </Card>
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

export default function ScenariosPage() {
  const me = useMe().data;
  const scenarios = useScenarios();
  const run = useRunScenario();
  const reset = useResetScenarios();
  const [mode, setMode] = useState<Mode>('board');
  const canRun = !!me?.operator;
  // Only a report that says so switches the runs off: an older server, or one not answering yet, keeps them.
  const playerOff = useHealth().data?.demo === false;
  const current = scenarios.data?.run ?? null;
  const busy = isPlaying(current) ? `A run of ${current?.scenario} is still playing` : '';

  const start = (s: Scenario) =>
    run.mutate(
      { id: s.id, mode },
      {
        onSuccess: () =>
          notifications.show({
            color: 'teal',
            title: `${s.id} started`,
            message: `${humanize(mode)} mode. The case appears in a few seconds.`,
          }),
        onError: (e) =>
          notifications.show({ color: 'red', title: `${s.id} did not start`, message: describeError(e) }),
      },
    );

  // The induction prompt leads the page on an instance, as the owner's questionnaire is designed; the demo, whose
  // profile is a recording nobody answers, keeps it below the fold, under the scenarios, so the guided path comes first.
  const induction = me?.approver ? <InductionPrompt below={DEMO} /> : null;
  return (
    <>
      {DEMO ? null : induction}
      <PageHeader
        title="Scenarios"
        subtitle="Each scenario plays a real failure into the production: HL7 files into the ADT folder and faults on the downstream system. Shutter opens a case, investigates, checks the plan at the gate, asks a person, and verifies the result at the receiver."
        actions={
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
                        color: 'teal',
                        title: 'Reset',
                        message: 'The downstream system and the folders are clear.',
                      }),
                    onError: (e) =>
                      notifications.show({ color: 'red', title: 'Reset failed', message: describeError(e) }),
                  })
                }
              >
                Reset
              </Button>
            </span>
          </Tooltip>
        }
      />
      <Stack gap="md">
        {/* The demo's guided path through the recorded cases: the first thing a judge sees */}
        {DEMO ? <StartHere /> : null}
        {playerOff ? (
          <Alert color="gray" variant="light" title="The Scenario Player is switched off">
            <Text size="sm">
              This is a site install, without the demo: there is no demo feed or downstream system to play the
              scenarios into, so they are listed here for reference only. Cases come from the feed items the
              site adds and from the productions that forward their failed deliveries to Shutter.
            </Text>
          </Alert>
        ) : (
          <Card padding="md">
            <Stack gap={6}>
              <Text fw={600} size="sm" id="mode-label">
                Investigation mode
              </Text>
              <SegmentedControl
                aria-labelledby="mode-label"
                value={mode}
                onChange={(v) => setMode(v as Mode)}
                data={MODES.map((m) => ({ value: m.value, label: m.label }))}
                w="fit-content"
              />
              <Text size="sm" c="dimmed">
                {MODES.find((m) => m.value === mode)?.hint}. The gate, the rehearsal and the approval are the
                same in every mode.
              </Text>
            </Stack>
          </Card>
        )}
        {current ? <RunBanner run={current} /> : null}
        {scenarios.isPending ? <PageSkeleton label="Loading the scenarios…" /> : null}
        {scenarios.isError ? (
          <ErrorAlert
            error={scenarios.error}
            title="The scenarios could not be read"
            onRetry={() => void scenarios.refetch()}
          />
        ) : null}
        {scenarios.data ? (
          <>
            {/* The cards' headings sit under this one, not under Start here; the layout does not show it */}
            <Title order={2} className={VisuallyHidden.classes.root}>
              Every scenario
            </Title>
            <SimpleGrid cols={{ base: 1, md: 2, xl: 3 }} spacing="md">
              {scenarios.data.scenarios.map((s) => (
                <ScenarioCard
                  key={s.id}
                  s={s}
                  mode={mode}
                  canRun={canRun}
                  playerOff={playerOff}
                  busy={busy || (run.isPending ? 'Starting…' : '')}
                  starting={run.isPending && run.variables?.id === s.id}
                  onRun={() => start(s)}
                />
              ))}
            </SimpleGrid>
          </>
        ) : null}
        {DEMO ? induction : null}
      </Stack>
    </>
  );
}
