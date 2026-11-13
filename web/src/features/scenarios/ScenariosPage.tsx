import {
  Alert,
  Anchor,
  Badge,
  Box,
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
import { useReducedMotion } from '@mantine/hooks';
import { useEffect, useMemo, useRef } from 'react';
import { Link } from 'react-router';
import { useListParams } from '@/lib/listParams';
import {
  isOpen,
  isPlaying,
  settlingCase,
  useCan,
  useCasePart,
  useCases,
  useHealth,
  useResetScenarios,
  useRunScenario,
  useMe,
  useScenarios,
  useSiteProfile,
} from '@/api/hooks';
import { replaysOnly, scenariosHidden, showsRoleBadges } from '@/api/can';
import type { AgentRun, CaseSummary, Mode, Scenario, ScenarioRun } from '@/api/types';
import { ENV, TRIAL } from '@/env/mode';
import { byEnv } from '@/env/copy';
import { PageHeader } from '@/components/PageHeader';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { ExpectedMark } from '@/components/ExpectedMark';
import { IdentityBadge } from '@/components/IdentityBadge';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PageSkeleton } from '@/components/PageSkeleton';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { StackTable } from '@/components/StackTable';
import { caseOutcome, caseState, PROVENANCE, proposedWrites, ranOnIris, writes } from '@/lib/status';
import { describeError } from '@/lib/errors';
import { formatAge, humanize } from '@/lib/format';
import { playedFor } from '@/lib/proof';
import { INSTALL_LINK, INSTALL_URL } from '@/lib/liveAgents';
import { traceScreenshot } from '@/lib/screenshots';
import { isDemoPolicy } from '@/features/site-profile/profile';
import type { Tone } from '@/lib/tone';
import { useTechnical } from '@/stores/appearance';
import { HINT_EVENTS } from '@/theme';
import { landOn } from '@/features/guide/reveal';
import { caseOf } from '@/features/guide/places';
import { EXECUTION, routeNext, runCase, runExecution, SINGLE_ROUTE } from './execution';
import { MoreAbout } from './MoreAbout';
import { ScenarioDiagram } from './ScenarioDiagram';
import { StartHere } from './StartHere';
import { ModeName, ScenariosHero, TryFirst } from './TryFirst';
import {
  hl7Events,
  recordedLine,
  REPLAY_ONLY,
  resetNeedsWords,
  runNeedsWords,
  scenarioCount,
  SCENARIOS_LEAD,
  splitSummary,
} from './scenarioText';

const ALL_MODES: { value: Mode; label: string; hint: string }[] = [
  {
    value: 'board',
    label: 'Board',
    hint: "Four AI Hub agents. Three specialists read the sealed evidence at once, each from one angle: the message, the encounter's history, the impact on the receiver. A coordinator weighs their findings and proposes one plan, with reasons.",
  },
  {
    value: 'policy',
    label: 'Site policy',
    hint: "How a hospital would run it. Failures the catalogue recognises are settled by the site's written policy, with no model; anything it doesn't recognise goes to the board.",
  },
  {
    value: 'single',
    label: 'Single investigator',
    // The trial never calls itself live (DESIGN.md 1.3): there the card's badge says it has no recording instead
    hint: byEnv({
      live: 'One AI Hub agent with the same evidence and tools proposes the plan alone, to compare with the board. Live only, so not in the trial.',
      trial:
        'One AI Hub agent with the same evidence and tools proposes the plan alone, to compare with the board.',
    }),
  },
  {
    value: 'rules',
    label: 'Rules only',
    hint: 'No agents: the baseline. Shutter resends the message unchanged unless the gate objects, as a plain Resend would. In S8 one gate check is lifted on purpose, to show what that writes.',
  },
];

/**
 * The single investigator's runs were never recorded, so it has nothing to replay: the trial cannot play it, nor can a
 * sign-in whose runs replay the recorded agents (`replayOnly`, 1.4.4: the online demo's account).
 */
const notRecorded = (mode: Mode, replayOnly = false) => mode === 'single' && (TRIAL || replayOnly);

const NOT_RECORDED = TRIAL ? 'Not in the trial: no recording' : REPLAY_ONLY.notRecorded;

/** The modes that can be played here. All four are always shown; the one that can't says so and can't be chosen. */
const modesFor = (replayOnly = false) => ALL_MODES.filter((m) => !notRecorded(m.value, replayOnly));

const modeLabel = (mode: Mode) => ALL_MODES.find((m) => m.value === mode)?.label ?? humanize(mode);

/** A filter or a mode stays on the page: the address changes, Back keeps its place, and the page does not jump to its top. */

/** What every mode keeps, said once above the modes; the one exemption, S8's in Rules only, is in that mode's hint. */
const MODES_INTRO =
  "The mode decides who proposes the plan. In every mode the same gate checks the plan, and a person or the site's policy releases any write.";

/** Whether the scenario is defined for the mode: one that names its modes isn't for the others. */
const definedFor = (s: Scenario, mode: Mode) => !s.expected?.modes || s.expected.modes.includes(mode);

/** The element that says once why the public demo's Run and Reset are greyed out; they point to it. */
const LOOK_ONLY_WHY = 'scenarios-look-only';

/** Why nothing can be played on a site install: the server switches the Scenario Player off (CONTRACTS 12). */
const PLAYER_OFF = 'The Scenario Player is switched off on a site install, which has no demo';

/**
 * How the run executes or executed, as a badge from the provenance vocabulary and a sentence, both read from what the
 * run records and never from the address or the account (execution.ts). A run on IRIS that the server did not mark as
 * a replay claims nothing until its own case's agent runs say what ran, so a fallback is never called live.
 */
function RunExecuted({ run, own }: { run: ScenarioRun; own: CaseSummary | undefined }) {
  const ask = !TRIAL && !run.replay && !!own;
  const runs = useCasePart<AgentRun[]>(own?.caseId ?? '', 'runs', '/runs', ask && isOpen(own?.state), ask);
  const ofCase = ask && own && runs.data !== undefined ? ranOnIris(own.mode, runs.data) : undefined;
  const how = runExecution(run, TRIAL, ofCase);
  return (
    <Group gap={6} wrap="wrap" align="center" data-testid="run-execution">
      {how.status ? <StatusBadge {...how.status} hint={undefined} /> : null}
      {how.words ? (
        <Text size="sm" span>
          {how.words}
        </Text>
      ) : null}
    </Group>
  );
}

/**
 * Where a finished run leads: its own case, and never the Cases list or a case of an earlier run (`runCase`). Until the
 * case has opened the banner says so and offers no link. Then what to look at there, where its trace is, and for the
 * short route's three the step after it, as words: nothing here starts the next run.
 */
function RunNext({ run, cases }: { run: ScenarioRun; cases: CaseSummary[] | undefined }) {
  const own = cases ? runCase(cases, run, TRIAL) : undefined;
  // The trial has recordings of some modes only: a run in another says so, and names the recording there is
  const other = TRIAL && cases && !own ? caseOf(cases, run.scenario) : undefined;
  const route = routeNext(run.scenario, run.mode);
  // The trial has no IRIS behind it, so a case's Message trace is a note there; its one picture of a trace is S8's
  const picture = TRIAL && cases ? caseOf(cases, 'S8', 'board') : undefined;
  const pictured = picture && traceScreenshot(picture) ? picture : undefined;
  const to = (id: string) => `/cases/${encodeURIComponent(id)}`;
  return (
    <Stack gap={6} align="flex-start" data-testid="run-next">
      {own ? (
        <Button component={Link} to={to(own.caseId)} size="xs" data-tour-action="open-run-case">
          Open its case, {own.caseId}
        </Button>
      ) : other ? (
        <Text size="sm">
          The trial has no recording of {run.scenario} in {modeLabel(run.mode)} mode. Its recorded case is{' '}
          <Anchor component={Link} to={to(other.caseId)} inherit underline="always">
            {other.caseId}, played in {modeLabel(other.mode as Mode)} mode
          </Anchor>
          .
        </Text>
      ) : cases ? (
        <Text size="sm">
          {byEnv({
            live: 'The production does the rest: its case opens in a few seconds, and its link appears here.',
            trial: 'The trial has no recording of its case.',
          })}
        </Text>
      ) : null}
      {own && route ? <Text size="sm">{route.look}</Text> : null}
      {own ? (
        <Text size="sm">
          {byEnv({
            live: "In IRIS: Message trace on the case opens its own session in IRIS's Visual Trace.",
            trial:
              pictured && pictured.caseId !== own.caseId ? (
                <>
                  The trial runs in your browser, so this case&apos;s Message trace is a note of what it opens
                  on IRIS. The one trace pictured here is{' '}
                  <Anchor component={Link} to={to(pictured.caseId)} inherit underline="always">
                    a screenshot of an S8 Board case&apos;s trace, on {pictured.caseId}
                  </Anchor>
                  .
                </>
              ) : pictured ? (
                "In IRIS: Message trace on this case opens a screenshot of an S8 Board case's trace, taken on a test instance, not this case's own session."
              ) : (
                "The trial runs in your browser, so this case's Message trace is a note of what it opens on IRIS."
              ),
          })}
        </Text>
      ) : null}
      {route ? (
        <Text size="sm" fw={600}>
          {route.next}
        </Text>
      ) : null}
    </Stack>
  );
}

/**
 * The run's state above the cards: who proposes (the mode, in its title) apart from how it executes (`RunExecuted`),
 * and once done its own case and the next step (`RunNext`).
 */
function RunBanner({ run, cases }: { run: ScenarioRun; cases: CaseSummary[] | undefined }) {
  const own = cases && run.state === 'done' ? runCase(cases, run, TRIAL) : undefined;
  if (run.state === 'queued')
    return (
      <Alert
        color="blue"
        variant="light"
        icon={<Loader size={16} />}
        title={`${run.scenario} is queued (${humanize(run.mode)})`}
      >
        <Stack gap={6}>
          <Text size="sm">The scenario player starts it in a moment.</Text>
          <RunExecuted run={run} own={undefined} />
        </Stack>
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
        <Stack gap={6}>
          <Text size="sm">
            {run.step ? `Now ${run.step}.` : 'Starting.'} Files delivered so far:{' '}
            {run.files.length ? run.files.join(', ') : 'none'}.
          </Text>
          <RunExecuted run={run} own={undefined} />
        </Stack>
      </Alert>
    );
  if (run.state === 'done')
    return (
      <Alert
        color="blue"
        variant="light"
        title={`${run.scenario} played (${humanize(run.mode)})${TRIAL ? '' : `, ${formatAge(run.finishedAt)}`}`}
      >
        <Stack gap="xs">
          <RunExecuted run={run} own={own} />
          <Text size="sm">
            Delivered {run.files.join(', ') || 'no files'}.
            {run.timeouts.length ? ` The case did not reach ${run.timeouts.join(', ')} in time.` : ''}
          </Text>
          <RunNext run={run} cases={cases} />
        </Stack>
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
              <Box component="span" display="inline-flex">
                <IdentityBadge hue="gray">or {humanize(a)}</IdentityBadge>
              </Box>
            </Tooltip>
          ))}
        {incident ? <WritesBadge n={incidentWrites} inAll /> : <WritesBadge n={e.write ? 1 : 0} />}
      </Group>
      {e.blocked_by ? (
        <Group gap={6} wrap="wrap" align="center">
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
  runNeeds,
  playerOff,
  busy,
  onRun,
  starting,
  lookOnly,
  replayOnly,
}: {
  s: Scenario;
  mode: Mode;
  /** The latest case among the newest cases the page read, when it is there. */
  found: CaseSummary | undefined;
  canRun: boolean;
  /** Why Run is greyed out for someone who may not run scenarios (runNeedsWords). */
  runNeeds: string;
  playerOff: boolean;
  busy: string;
  onRun: () => void;
  starting: boolean;
  /** The public demo's role: Run is greyed out, its reason said once at the top of the page. */
  lookOnly: boolean;
  /** The sign-in's runs replay the recorded agents (1.4.4): Run says so. */
  replayOnly: boolean;
}) {
  const technical = useTechnical();
  // With the player switched off there is no mode to play in, so no row is marked for one.
  const defined = playerOff || definedFor(s, mode);
  const modes = (s.expected?.modes ?? [])
    .filter((m) => modesFor(replayOnly).some((x) => x.value === m))
    .map(modeLabel);
  const why = playerOff
    ? PLAYER_OFF
    : lookOnly
      ? runNeeds
      : !defined
        ? `${s.id} is not defined for ${modeLabel(mode)} mode: it would not end as its row says. Its modes: ${modes.join(', ')}.`
        : !canRun
          ? runNeeds
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
      <StackTable.Th scope="row" style={{ verticalAlign: 'top', fontWeight: 'inherit', flex: '1 1 100%' }}>
        <Box className="scenario-cell">
          <Group gap={8} wrap="nowrap" align="baseline" className="scenario-title">
            <Text span fz={13} fw={600} className="mono" miw={34} style={{ flex: 'none' }}>
              {s.id}
            </Text>
            <Text span size="md" fw={650}>
              {s.title}
            </Text>
          </Group>
          <Text size="sm" c="dimmed" className="scenario-summary">
            {first}
          </Text>
          <ScenarioDiagram scenario={s} mode={mode} />
          {rest ? (
            <Box className="scenario-more">
              <MoreAbout about={s.id}>
                <Text size="sm">{rest}</Text>
              </MoreAbout>
            </Box>
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
        </Box>
      </StackTable.Th>
      <StackTable.Td
        data-label="What should happen"
        data-label-hidden
        className="stack-line"
        style={{ verticalAlign: 'top' }}
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
      <StackTable.Td
        data-label="Play"
        data-label-hidden
        className="stack-line scenario-run"
        style={{ verticalAlign: 'top' }}
      >
        <Stack gap={4} align="flex-start">
          <Tooltip
            label={
              why ||
              (replayOnly ? REPLAY_ONLY.play(s.id, humanize(mode)) : `Play ${s.id} in ${humanize(mode)} mode`)
            }
            multiline
            maw={260}
          >
            <span>
              <Button
                size="xs"
                variant="light"
                leftSection={<IconPlayerPlay size={14} />}
                disabled={!!why}
                loading={starting}
                onClick={onRun}
                aria-label={`Run ${s.id}`}
                aria-describedby={lookOnly ? LOOK_ONLY_WHY : undefined}
              >
                Run
              </Button>
            </span>
          </Tooltip>
          {/* The reason, in words a keyboard or a screen reader reaches; a row not in the mode says it above, and the
              public demo's is said once at the top of the page */}
          {why && defined && !lookOnly ? (
            <Text size="xs" c="dimmed" maw={160}>
              {why}
            </Text>
          ) : null}
        </Stack>
      </StackTable.Td>
    </StackTable.Tr>
  );
}

/**
 * The induction prompt (the site profile's questionnaire): an approver sees it until the site's answers are saved. It leads
 * the page on an instance; `below` places it under the scenarios, where the demo keeps it. On the demo's own answers it
 * says so, as the site profile does, rather than calling them the shipped ones.
 */
function InductionPrompt({ below = false }: { below?: boolean }) {
  const profile = useSiteProfile().data;
  if (!profile || profile.source === 'api') return null;
  return (
    <Alert
      color="blue"
      variant="light"
      mb={below ? 0 : 'md'}
      title={
        isDemoPolicy(profile.source)
          ? "Shutter is running on the demo's answers"
          : 'Shutter is running on the shipped site profile'
      }
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

/**
 * How runs execute here, under the modes and apart from them: the mode is who proposes, and this is whether a model is
 * called. The trial plays recordings in the browser; a sign-in without the live agents replays the recorded agents on
 * IRIS; a sign-in with them is promised nothing before the run, since only a case's own agent runs say what ran. Each
 * also names the way to live agents where there are none, with the link to the install steps.
 */
function HowRunsExecute({ replayOnly }: { replayOnly: boolean }) {
  const status = TRIAL ? PROVENANCE.recording : replayOnly ? PROVENANCE.replay : undefined;
  const words = TRIAL ? EXECUTION.trial : replayOnly ? EXECUTION.replay : EXECUTION.live;
  const route = TRIAL ? EXECUTION.trialRoute : replayOnly ? EXECUTION.replayRoute : '';
  return (
    <Stack
      gap={4}
      mt="sm"
      data-testid="how-runs-execute"
      component="section"
      aria-labelledby="how-runs-execute"
    >
      <Group gap={8} wrap="wrap" align="center">
        <Text fw={650} size="md" id="how-runs-execute" component="h3" m={0}>
          How a run executes here
        </Text>
        {status ? <StatusBadge {...status} hint={undefined} /> : null}
      </Group>
      <Text size="sm" maw="80ch">
        {EXECUTION.lead} {words}
        {route ? (
          <>
            {' '}
            {route} See{' '}
            <Anchor href={INSTALL_URL} target="_blank" rel="noreferrer" inherit underline="always">
              {INSTALL_LINK}
              <VisuallyHidden> Shutter with your own model key (opens in a new tab)</VisuallyHidden>
            </Anchor>
            .
          </>
        ) : null}
      </Text>
    </Stack>
  );
}

/**
 * The modes, once, as a choice of cards: who proposes the plan, in each card's own words (the approved descriptions,
 * every one in view without choosing its mode), and how many scenarios each mode plays. The cards are level from a
 * laptop up, each count at its card's foot, and stack on a phone. Where the user may not run scenarios (`lookOnly`) the
 * choice stays, since it is how the list below reads in that mode, and starts where the hospital plays; only Run is
 * greyed out. How a run executes is said under the cards, apart from who proposes (`HowRunsExecute`).
 */
function RunModes({
  mode,
  onChange,
  scenarios,
  lookOnly,
  defaultMode,
  replayOnly = false,
}: {
  mode: Mode;
  onChange: (m: Mode) => void;
  scenarios: Scenario[] | undefined;
  lookOnly: boolean;
  defaultMode: Mode;
  /** The sign-in's runs replay the recorded agents (1.4.4): a mode with no recording can't be chosen. */
  replayOnly?: boolean;
}) {
  return (
    <Box data-tour="scenarios-mode">
      <Radio.Group
        value={mode}
        onChange={(v) => onChange(v as Mode)}
        name="run-mode"
        label={
          <Text span fw={650} fz="xl">
            {lookOnly ? 'Investigation modes' : 'Run mode'}
          </Text>
        }
        description={`${lookOnly ? 'Pick one to read the list below in it.' : 'Every Run button below uses it.'} ${MODES_INTRO}`}
        styles={{ description: { fontSize: 'var(--mantine-font-size-sm)' } }}
      >
        <SimpleGrid cols={{ base: 1, sm: 2, lg: ALL_MODES.length }} spacing="sm" mt="sm">
          {ALL_MODES.map((m) => {
            const n = scenarios?.filter((s) => definedFor(s, m.value)).length;
            const out = notRecorded(m.value, replayOnly);
            return (
              <Radio.Card
                key={m.value}
                value={m.value}
                radius="md"
                p="xs"
                className="mode-card"
                disabled={out}
                // Mantine's arrow keys walk the radios of one name and would stop dead on a disabled one
                name={out ? 'run-mode-not-recorded' : undefined}
                aria-labelledby={`mode-${m.value}-label`}
                aria-describedby={`mode-${m.value}-hint${scenarios || out ? ` mode-${m.value}-count` : ''}${out ? ` mode-${m.value}-route` : ''}`}
              >
                <Group gap="xs" wrap="nowrap" align="stretch">
                  <Radio.Indicator mt={2} disabled={out} style={{ flex: 'none' }} />
                  <Stack gap={6} style={{ minWidth: 0, flex: 1 }}>
                    <Group gap={6} align="baseline">
                      <Text size="md" fw={700} id={`mode-${m.value}-label`}>
                        <ModeName mode={m.value}>{m.label}</ModeName>
                      </Text>
                      {m.value === defaultMode ? (
                        <Text span size="sm" c="dimmed">
                          default
                        </Text>
                      ) : null}
                    </Group>
                    {/* Each mode's own words, in its card: read without choosing the mode, by eye and by screen reader */}
                    <Text id={`mode-${m.value}-hint`} size="sm" className="mode-hint">
                      {m.hint}
                    </Text>
                    {/* The mode that can't be chosen says the way to it, under why */}
                    {out ? (
                      <Text id={`mode-${m.value}-route`} size="sm" className="mode-hint">
                        {TRIAL ? SINGLE_ROUTE.trial : SINGLE_ROUTE.replay}
                      </Text>
                    ) : null}
                    <Box mt="auto">
                      {out ? (
                        <Badge
                          id={`mode-${m.value}-count`}
                          variant="light"
                          color="gray"
                          size="sm"
                          style={{ textTransform: 'none' }}
                        >
                          {NOT_RECORDED}
                        </Badge>
                      ) : scenarios && n !== undefined ? (
                        <PlaysBadge id={`mode-${m.value}-count`} n={n} of={scenarios.length} />
                      ) : null}
                    </Box>
                  </Stack>
                </Group>
              </Radio.Card>
            );
          })}
        </SimpleGrid>
      </Radio.Group>
      {lookOnly ? null : <HowRunsExecute replayOnly={replayOnly} />}
    </Box>
  );
}

/** Every scenario, filtered by what it should end in; the counts are the list's own. */
function AllScenarios({
  scenarios,
  mode,
  row,
}: {
  scenarios: Scenario[];
  mode: Mode;
  row: (s: Scenario) => React.ReactNode;
}) {
  // In the address with the run mode, so Back from a case returns to this list
  const [params, change] = useListParams();
  const outcome = params.get('outcome') ?? 'all';
  const setOutcome = (next: string) =>
    change((p) => {
      if (next === 'all') p.delete('outcome');
      else p.set('outcome', next);
    });
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
            {scenarioCount(scenarios.length, TRIAL)} Filter by what should happen in {modeLabel(mode)} mode.
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
        <Text size="sm" className="diagrams-say">
          Diagrams show the scenario and the expected response, not the latest run.
        </Text>
        {/* What the badges say in short, written out once: none of them is a tab stop in this list */}
        <TechDetail label="How to read this list" kind="explain">
          <Text size="sm" maw="68ch">
            The small diagram draws what the scenario plays and, last, the end it expects in this mode, as
            What should happen does; a recorded run can differ, and its latest case says so. What should
            happen is the end the scenario expects: its action, &quot;or&quot; another answer the evaluation
            also accepts, and Stops on the reason code the gate or the dispatch should stop on. Latest case is
            the newest case the scenario opened, with its outcome in short: As expected when the outcome
            matches what the scenario expects, Not as expected when it differs.
          </Text>
        </TechDetail>
        <Table.ScrollContainer minWidth={690} className="stack-scroll">
          <StackTable className="stack-table stack-cards scenario-list" verticalSpacing="xs">
            <StackTable.Thead>
              <StackTable.Tr>
                <StackTable.Th>Scenario</StackTable.Th>
                <StackTable.Th>What should happen</StackTable.Th>
                <StackTable.Th>Latest case</StackTable.Th>
                <StackTable.Th>Play</StackTable.Th>
              </StackTable.Tr>
            </StackTable.Thead>
            <StackTable.Tbody>{shown.map(row)}</StackTable.Tbody>
          </StackTable>
        </Table.ScrollContainer>
      </Stack>
    </Card>
  );
}

/** The judges' path (`?trial=judge`) lands on the S8 card once per page, never again on a later visit to Scenarios. */
let judgeLanded = false;

/**
 * The judges' path: once the cards are drawn, the page lands on S8's, which plays in the mode the address chose (Rules
 * only), and its Run takes the focus, so Enter or a click plays it.
 */
function useJudgeLanding(ready: boolean) {
  const reduced = useReducedMotion();
  useEffect(() => {
    if (!ENV.judgePath || judgeLanded || !ready) return;
    const card = document.querySelector<HTMLElement>('[data-first="S8"]');
    if (!card) return;
    judgeLanded = true;
    card.querySelector<HTMLElement>('[data-tour-action="run-S8"]')?.focus({ preventScroll: true });
    // Not stopped on unmount: a second effect run (StrictMode) would find it landed and leave the page where it was
    landOn(card, reduced);
  }, [ready, reduced]);
}

/** The cards a visitor can be sent to start at: an id as the scenarios are named, so the address can name no other element. */
const CARD_ID = /^S\d+[a-z]?$/;

/**
 * Home's way in (`?start=S2`): once the cards are drawn the page lands on that card and its Run takes the focus, so the
 * next choice is Run itself. Nothing is pressed: arriving starts no run. The address then drops `start`, so Back from
 * the run's case, or a reload, shows the page where the reader left it and not the card again.
 */
function useStartLanding(ready: boolean) {
  const reduced = useReducedMotion();
  const [params, change] = useListParams();
  const start = params.get('start');
  const landed = useRef<string | null>(null);
  useEffect(() => {
    if (!start || !ready) return;
    if (landed.current !== start && CARD_ID.test(start)) {
      const card = document.querySelector<HTMLElement>(`[data-first="${start}"]`);
      if (card) {
        landed.current = start;
        card.querySelector<HTMLElement>(`[data-tour-action="run-${start}"]`)?.focus({ preventScroll: true });
        landOn(card, reduced);
      }
    }
    // `change` is made anew on every render, so this runs on each: it returns at once when the address names no start
    change((p) => p.delete('start'));
  }, [ready, start, reduced, change]);
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
  const canRun = can.scenarios;
  // Runs from a sign-in without the live agents replay the recorded agents (1.4.4, the online demo's account); the trial
  // replays every run anyway and says so in its own words
  const replayOnly = !TRIAL && replaysOnly(can);
  const playable = modesFor(replayOnly);
  // Resetting the shared demo is a right of its own (1.4.3): a judge runs scenarios and does not reset them. A server
  // older than that sends no `reset`, and resolveCan takes `scenarios` for it.
  const canReset = can.reset ?? canRun;
  // The reasons say what the sign-in lacks, never that it needs a role the user menu shows it has (the demo's viewer and
  // a judge show the operator and approver badges)
  const badges = showsRoleBadges(useMe().data);
  const runNeeds = runNeedsWords(badges);
  // Only a report that says so switches the runs off: an older server, or one not answering yet, keeps them.
  const playerOff = useHealth().data?.demo === false;
  // A role that operates but may not run or reset (the public demo's before 1.4.4): Run and Reset greyed out, its own
  // three cards, a line saying why. A site install has no demo hospital whichever role reads it, so its own notice speaks there.
  const hidden = scenariosHidden(can) && !playerOff;
  // Where nobody here can run one, the list starts in the mode the hospital plays; the role can arrive after the first paint
  const defaultMode: Mode = hidden ? 'policy' : 'board';
  const [params, change] = useListParams();
  const picked = playable.find((m) => m.value === params.get('mode'))?.value;
  const mode = picked ?? defaultMode;
  const setMode = (next: Mode) => change((p) => p.set('mode', next));
  useJudgeLanding(!!scenarios.data);
  useStartLanding(!!scenarios.data);
  const current = scenarios.data?.run ?? null;
  // A run that has just finished has opened its case: the cases are read again at once, so the banner's link to the
  // run's own case does not wait for the list's next quiet poll
  const refetchCases = cases.refetch;
  const finished = current?.state === 'done' ? current.startedAt : '';
  useEffect(() => {
    if (finished) void refetchCases();
  }, [finished, refetchCases]);
  const busy = isPlaying(current) ? `A run of ${current?.scenario} is still playing` : '';
  /** Why Reset is disabled now, or "". Reset stays on while a case settles: it is the way out of one that never does. */
  const resetWhy = playerOff ? PLAYER_OFF : !canReset ? resetNeedsWords(badges, canRun) : busy;
  const settling = settlingCase(scenarios.data);
  const runBusy =
    busy || (settling ? `${settling.caseId} is still settling: a new run now would abandon it` : '');

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
                message: `${humanize(m)} mode${replayOnly ? `, ${REPLAY_ONLY.started}` : ''}. The case appears in a few seconds.`,
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
      : hidden
        ? runNeeds
        : !definedFor(s, m)
          ? `${s.id} is not defined for ${modeLabel(m)} mode`
          : !playable.some((x) => x.value === m)
            ? replayOnly
              ? REPLAY_ONLY.notRecordedWhy
              : `${modeLabel(m)} mode has no recordings here`
            : !canRun
              ? runNeeds
              : runBusy || pending;

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
        lead={hidden || playerOff ? SCENARIOS_LEAD.lookOnly : byEnv(SCENARIOS_LEAD)}
        actions={
          <Stack gap={4} align="flex-end">
            <Tooltip
              label={resetWhy || 'Clear the downstream system, the folders and the running scenario'}
              multiline
              maw={260}
            >
              <span>
                <Button
                  variant="default"
                  leftSection={<IconRefresh size={16} />}
                  aria-describedby={hidden ? LOOK_ONLY_WHY : undefined}
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
            {resetWhy && !hidden ? (
              <Text size="xs" c="dimmed" ta="right">
                {resetWhy}
              </Text>
            ) : null}
          </Stack>
        }
      />
      <Stack gap="lg">
        <ScenariosHero demo={hidden} />
        {hidden ? (
          <Text size="md" id={LOOK_ONLY_WHY} maw="68ch">
            {byEnv({
              live: 'This hospital plays its stories by itself, and this sign-in reads and approves: it does not run or reset a scenario. The trial and your own instance run them.',
              trial:
                "The online demo's hospital plays its stories by itself, so this role cannot run one. To run one, switch to Operator or Approver in the menu at the top right.",
            })}
          </Text>
        ) : null}
        {current ? <RunBanner run={current} cases={cases.data?.items} /> : null}
        {/* Always rendered, loading or not, so the guide's first step has its target; a site install has nothing to try,
            and the list below stands as its reference */}
        {playerOff ? null : (
          <TryFirst
            scenarios={scenarios.data?.scenarios}
            failed={scenarios.isError}
            why={whyNot}
            starting={(s, m) => run.isPending && run.variables?.id === s.id && run.variables?.mode === m}
            onRun={start}
            demo={hidden}
            whyId={LOOK_ONLY_WHY}
            chosen={mode}
            replayed={replayOnly}
          />
        )}
        {playerOff ? (
          <Alert color="gray" variant="light" title="The Scenario Player is switched off">
            <Text size="sm">
              This is a site install, without the demo: there is no demo feed or downstream system to play the
              scenarios into, so they are listed here for reference only. Cases come from the feed items the
              site adds and from the productions that forward their failed deliveries to Shutter.
            </Text>
          </Alert>
        ) : (
          <RunModes
            mode={mode}
            onChange={setMode}
            scenarios={scenarios.data?.scenarios}
            lookOnly={hidden}
            defaultMode={defaultMode}
            replayOnly={replayOnly}
          />
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
            row={(s) => (
              <ScenarioRow
                key={s.id}
                s={s}
                mode={mode}
                found={s.latestCase ? byId.get(s.latestCase.caseId) : undefined}
                lookOnly={hidden}
                replayOnly={replayOnly}
                canRun={canRun}
                runNeeds={runNeeds}
                playerOff={playerOff}
                busy={runBusy || pending}
                starting={run.isPending && run.variables?.id === s.id && run.variables?.mode === mode}
                onRun={() => start(s)}
              />
            )}
          />
        ) : null}
        {/* The demo's guided path through the recorded cases, past the first three */}
        {TRIAL ? <StartHere /> : null}
        {TRIAL ? induction : null}
      </Stack>
    </>
  );
}
