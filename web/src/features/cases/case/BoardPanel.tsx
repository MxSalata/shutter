import {
  Accordion,
  Badge,
  Group,
  List,
  SimpleGrid,
  Stack,
  Text,
  Tooltip,
  VisuallyHidden,
} from '@mantine/core';
import { IconMessageExclamation, IconUsers } from '@tabler/icons-react';
import { type ComponentType, Fragment, lazy, Suspense, useState } from 'react';
import { useRuns, useSettings } from '@/api/hooks';
import type { AgentRun, Mode } from '@/api/types';
import { AgreementDots } from '@/components/AgreementDots';
import { CodeChip } from '@/components/CodeChip';
import { ErrorAlert } from '@/components/ErrorAlert';
import { MemberCard } from '@/components/MemberCard';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { JsonBlock } from '@/components/JsonBlock';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { TRIAL } from '@/env/mode';
import { costAtPrice } from '@/lib/cost';
import { catalogueEntriesOf, EVIDENCE_REFS, evidenceSection } from '@/lib/evidenceRefs';
import { asArray, asObject } from '@/lib/json';
import { formatDuration, formatInt, formatUsd, humanize, plural } from '@/lib/format';
import { memberIdentity, SPECIALISTS } from '@/lib/hues';
import { PROVENANCE } from '@/lib/status';
import { useTechnical } from '@/stores/appearance';
import { describeEntry } from './derive';
import { showEvidence } from './evidenceLinks';
import { MoreToggle } from './MoreToggle';
import type { RecordingToggleProps } from './RecordingToggle';
import { agreementOf, answered, boardRounds, dispositionOf, latestRound, resultOf } from './boardRounds';
import type { BoardRound } from './boardRounds';
import { investigationRuns } from './runClock';
import { RunTimeline } from './RunTimeline';
import { NotYet, Section } from './Section';

/** Small counts in words, as the board's note says them. */
const NUMBERS: Record<number, string> = { 1: 'One', 2: 'Two', 3: 'Three', 4: 'Four', 5: 'Five' };

/** A finding's lists, in the order the cards show them. */
const LISTS: [string, string][] = [
  ['violations', 'Violations'],
  ['superseding_evidence', 'Superseding evidence'],
  ['affected_systems', 'Affected systems'],
  ['unknowns', 'Unknown'],
  ['preconditions', 'Preconditions'],
  ['disagreements', 'Disagreements kept'],
];

/** A run's cost and tokens, and its provenance in full: inside the finding or the run, one click from the card. */
function RunStats({ run }: { run: AgentRun }) {
  const replay = run.mode === 'replay';
  const prices = useSettings().data?.prices;
  // A replay costs nothing now; its tokens are the recorded run's, so they give what that run cost.
  const recorded = replay ? costAtPrice(run, prices) : undefined;
  const cost = replay
    ? recorded !== undefined
      ? `${formatUsd(recorded)} when recorded, nothing now`
      : 'nothing now'
    : formatUsd(run.costUsd) || '$0.00';
  return (
    <Stack gap={4}>
      <Group gap={6} wrap="wrap">
        <StatusBadge
          {...PROVENANCE[replay ? 'replay' : 'live']}
          size="xs"
          label={
            replay
              ? `${PROVENANCE.replay.label}${run.model ? ` · ${run.model}` : ''}`
              : `${PROVENANCE.live.label} · ${run.model}`
          }
          hint={
            replay
              ? `Replayed from a recorded live run${run.model ? ` on ${run.model}` : ''}: no model was called now`
              : `A live run on ${run.model}`
          }
        />
        {run.status !== 'ok' ? <StatusBadge tone="blocking" size="xs" label={humanize(run.status)} /> : null}
      </Group>
      {replay && !Number(run.promptTokens) && !Number(run.completionTokens) ? (
        <Text size="xs" c="dimmed">
          No model call now: the recording's findings were replayed
          {run.toolCallCount ? `, with its ${run.toolCallCount} tool calls` : ''}.
        </Text>
      ) : (
        <Text size="xs" c="dimmed">
          {formatInt(run.promptTokens)} in · {formatInt(run.completionTokens)} out
          {Number(run.cacheReadTokens) || Number(run.cacheCreationTokens)
            ? ` · cache ${formatInt(run.cacheReadTokens)} read, ${formatInt(run.cacheCreationTokens)} written`
            : ''}
          {' · '}
          {cost} · {formatDuration(run.durationMs) || '0 ms'}
          {run.toolCallCount ? ` · ${run.toolCallCount} tool calls` : ''}
        </Text>
      )}
      {run.error ? (
        <Text size="xs" c="red">
          {run.error}
        </Text>
      ) : null}
    </Stack>
  );
}

function ResultLists({ result, omit = [] }: { result: Record<string, unknown>; omit?: string[] }) {
  return (
    <>
      {LISTS.filter(([key]) => !omit.includes(key)).map(([key, label]) => {
        const items = asArray(result[key]);
        if (!items.length) return null;
        return (
          <Stack gap={2} key={key}>
            <Text size="xs" fw={600} c="dimmed">
              {label}
            </Text>
            <List size="sm" spacing={2}>
              {items.map((x, i) => (
                <List.Item key={i}>{describeEntry(x)}</List.Item>
              ))}
            </List>
          </Stack>
        );
      })}
    </>
  );
}

function ToolCalls({ run }: { run: AgentRun }) {
  if (!run.toolCalls?.length) return null;
  return (
    <Accordion variant="contained" chevronPosition="left">
      <Accordion.Item value="calls">
        <Accordion.Control>
          <Text size="xs">Tool calls ({run.toolCalls.length})</Text>
        </Accordion.Control>
        <Accordion.Panel>
          <Stack gap="xs">
            {run.toolCalls.map((t) => (
              <Stack key={t.seq} gap={2}>
                <Text size="xs" fw={600}>
                  {t.seq}. {t.name} {t.ok ? '' : '(failed)'} · {formatDuration(t.durationMs)}
                </Text>
                <JsonBlock value={t.arguments} label={`${t.name} arguments`} />
                {t.resultPreview ? (
                  <Text size="xs" c="dimmed" className="mono-wrap">
                    {t.resultPreview}
                  </Text>
                ) : null}
              </Stack>
            ))}
          </Stack>
        </Accordion.Panel>
      </Accordion.Item>
    </Accordion>
  );
}

/** A run's facts in one line, always on its card: "Replay · claude-opus-5-5 · 14.6 s · 3 steps · 5 tool calls · message 16615". */
function RunLine({ run, portalBase }: { run: AgentRun; portalBase: string }) {
  const technical = useTechnical();
  const parts = [
    run.mode === 'replay' ? 'Replay' : run.mode === 'live' ? 'Live' : humanize(run.mode),
    run.model,
    formatDuration(run.durationMs),
    // "steps" is the plain word for the agent's iterations; Technical names them
    run.iterations ? plural(Number(run.iterations), technical ? 'iteration' : 'step') : '',
    run.toolCallCount ? plural(Number(run.toolCallCount), 'tool call') : '',
  ].filter(Boolean);
  return (
    <span className="run-line">
      {parts.join(' · ')}
      {run.ensMessageId ? (
        <>
          {' · '}
          <PortalLink
            href={
              run.messageLink ||
              `${portalBase}EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(run.ensMessageId)}`
            }
            what={`message ${run.ensMessageId}, the agent's request and answer`}
            size="xs"
          >
            {`message ${run.ensMessageId}`}
          </PortalLink>
        </>
      ) : null}
      {run.status && run.status !== 'ok' ? ` · ${humanize(run.status)}` : ''}
    </span>
  );
}

/** A cited section's chip, in a word or two; the section's own title is on the Evidence tab it opens. */
const CHIPS: Record<string, string> = {
  message: 'HL7 message',
  validation: 'Schema validation',
  error: 'Connector error',
  operation: 'Failed operation',
  route: 'Route',
  ward_state: 'Encounter',
  receipt: 'Receipt',
  timeline: 'Timeline',
  later_event: 'Later events',
};

/** The evidence sections a run cites, in the Evidence tab's order, and the catalogue entries it names. */
function citedBy(run: AgentRun): { refs: string[]; entries: string[] } {
  const refs = asArray(resultOf(run).evidence_refs).filter((r): r is string => typeof r === 'string');
  return {
    refs: EVIDENCE_REFS.filter((r) => refs.includes(r)),
    entries: catalogueEntriesOf(refs),
  };
}

/**
 * What a member cited, counted on its card ("Cited 8 evidence sections", "and catalogue entry E7"), with a chip per
 * section in "Which ones" (a data detail, open in Technical): each opens that section on the Evidence tab.
 */
function Citations({ run, name, receiver }: { run: AgentRun; name: string; receiver?: string }) {
  const { refs, entries } = citedBy(run);
  if (!refs.length && !entries.length) return null;
  return (
    <Stack gap={4}>
      <Text size="sm">
        {refs.length ? `Cited ${plural(refs.length, 'evidence section')}` : 'Cited'}
        {entries.length ? (
          <>
            {refs.length ? ' and ' : ' '}
            <Term term="catalogue-entry">
              {entries.length === 1 ? 'catalogue entry' : 'catalogue entries'}
            </Term>{' '}
            {entries.map((e, i) => (
              <Fragment key={e}>
                {i ? ', ' : ''}
                <CodeChip>{e}</CodeChip>
              </Fragment>
            ))}
          </>
        ) : null}
      </Text>
      {refs.length ? (
        <TechDetail
          kind="data"
          label={
            <>
              Which ones<VisuallyHidden component="span">{`, ${name}`}</VisuallyHidden>
            </>
          }
        >
          <Group gap={6} wrap="wrap">
            {refs.map((ref) => {
              const section = evidenceSection(ref, receiver);
              return section ? (
                <Tooltip key={ref} label={`Open ${section.title} on the Evidence tab`}>
                  <Badge
                    size="sm"
                    variant="outline"
                    color="gray"
                    component="button"
                    type="button"
                    onClick={() => showEvidence(ref)}
                    style={{ textTransform: 'none', cursor: 'pointer', height: 'auto', whiteSpace: 'normal' }}
                  >
                    {CHIPS[ref] ?? section.title}
                  </Badge>
                </Tooltip>
              ) : null;
            })}
          </Group>
        </TechDetail>
      ) : null}
    </Stack>
  );
}

/**
 * An operation key (`BEDMGR^HOSP^MRN1008^ENC-1008^transfer^2026-10-15T08:20:00Z`) in a sentence, as a wrapping code:
 * without a bracket, comma or semicolon round it, or the full stop after it ("(set by BEDMGR^...^08:20:00Z)").
 */
const KEY = /([A-Z][A-Z0-9]*(?:\^[^\s^(),;]+){2,}\^[^\s^(),;]*[^\s^(),;.])/;

function WithKeys({ text }: { text: string }) {
  const parts = text.split(KEY);
  return (
    <>{parts.map((p, i) => (i % 2 ? <CodeChip key={i}>{p}</CodeChip> : <Fragment key={i}>{p}</Fragment>))}</>
  );
}

/** The details of a member's finding: its question, its reasoning in full, its lists, its cost and its tool calls. */
function FindingDetail({ run }: { run: AgentRun }) {
  const result = resultOf(run);
  return (
    <Stack gap="xs">
      {run.member?.perspective ? (
        <Text size="xs" c="dimmed">
          {run.member.perspective}
        </Text>
      ) : null}
      <Text size="sm">{String(result.summary ?? run.finding?.summary ?? run.content ?? '')}</Text>
      <ResultLists result={result} />
      <RunStats run={run} />
      <ToolCalls run={run} />
    </Stack>
  );
}

/**
 * Trial pages only: the toggle for what this member was sent and did, with the recording under it, in a chunk of its
 * own. A live page has none of its words or code, and if the chunk cannot load the card is simply without the toggle.
 */
const LazyRecordingToggle = TRIAL
  ? lazy<ComponentType<RecordingToggleProps>>(() =>
      import('./RecordingToggle').catch(() => ({ default: () => null })),
    )
  : null;

function RecordingToggle(props: RecordingToggleProps) {
  return LazyRecordingToggle ? (
    <Suspense fallback={null}>
      <LazyRecordingToggle {...props} />
    </Suspense>
  ) : null;
}

/** The border of a card that dissented: two pixels in the attention tone, beside the badge that says it in words. */
const DISSENT_BORDER = {
  borderLeftColor: 'var(--mantine-color-yellow-outline)',
  borderRightColor: 'var(--mantine-color-yellow-outline)',
  borderBottomColor: 'var(--mantine-color-yellow-outline)',
  borderWidth: 2,
  borderTopWidth: 3,
};

/** The card's name, as its heading's words, with the id its region and toggles are named by. */
const nameOf = (run: AgentRun) => run.member?.name ?? humanize(run.memberCode);

/** Which sitting a card belongs to, on a case whose board sat more than once. */
function RoundMark({ id, round }: { id: string; round?: number }) {
  return round ? (
    <Text component="span" className="overline" id={id}>
      {`Round ${round}`}
    </Text>
  ) : null;
}

/**
 * A specialist agent as a card, in its member's hue: its name, what it proposed, its own confidence (its own report,
 * never the gate's), the run's facts in one line, what it cited, and the finding in full on demand. A specialist that
 * disagreed with the plan carries the Dissent badge and the dissent as the coordinator kept it, so dissent is read,
 * not hidden.
 */
function SpecialistCard({
  caseId,
  run,
  portalBase,
  dissent,
  kept,
  receiver,
  defineConfidence,
  round,
}: {
  caseId: string;
  run: AgentRun;
  portalBase: string;
  dissent: boolean;
  /** The dissent as the coordinator kept it, in a line: what the specialist proposed and why. */
  kept?: string;
  receiver?: string;
  /** The page's first confidence: its words carry their definition. */
  defineConfidence: boolean;
  /** The sitting's number, when the board sat more than once. */
  round?: number;
}) {
  const [open, setOpen] = useState(false);
  const [recording, setRecording] = useState(false);
  const result = resultOf(run);
  const key = String(run.id ?? run.memberCode);
  const name = nameOf(run);
  const confidence = Number(result.confidence ?? run.finding?.confidence);
  // A run with no answer can still hold a result (over its budget, kept for inspection only): no confidence to report
  const shown = answered(run) && Number.isFinite(confidence) && confidence > 0;
  const own = 'own confidence';
  return (
    <MemberCard
      member={run.memberCode}
      name={name}
      titleId={`agent-${key}`}
      {...(round ? { 'aria-labelledby': `agent-${key} agent-${key}-round` } : {})}
      badge={
        <>
          <RoundMark id={`agent-${key}-round`} round={round} />
          {dissent ? <StatusBadge tone="attention" label="Dissent" icon={IconMessageExclamation} /> : null}
        </>
      }
      meta={<RunLine run={run} portalBase={portalBase} />}
      // A recording is read at the board's full width, not in a third of it
      style={{
        minWidth: 0,
        ...(dissent ? DISSENT_BORDER : {}),
        ...(recording ? { gridColumn: '1 / -1' } : {}),
      }}
    >
      {answered(run) ? (
        <Group gap="xs" wrap="wrap">
          <DispositionBadge disposition={dispositionOf(run)} proposed />
        </Group>
      ) : (
        <Text size="sm" c="dimmed">
          No answer from this agent.
        </Text>
      )}
      {shown ? (
        <Text size="sm" data-testid="own-confidence">
          {'Its '}
          {defineConfidence ? (
            <Term definition="The agent's own report. The gate does not use it.">{own}</Term>
          ) : (
            own
          )}
          {`: ${Math.round(confidence * 100)}%`}
        </Text>
      ) : null}
      {kept ? <Text size="sm">{kept}</Text> : null}
      <Citations run={run} name={name} receiver={receiver} />
      <MoreToggle
        open={open}
        onToggle={() => setOpen((o) => !o)}
        controls={`agent-${key}-finding`}
        describedBy={`agent-${key}`}
        label="the finding"
      />
      {open ? (
        <div id={`agent-${key}-finding`}>
          <FindingDetail run={run} />
        </div>
      ) : (
        <div id={`agent-${key}-finding`} hidden />
      )}
      <RecordingToggle
        caseId={caseId}
        run={run}
        open={recording}
        onToggle={() => setRecording((o) => !o)}
        describedBy={`agent-${key}`}
      />
    </MemberCard>
  );
}

/**
 * The coordinator agent as the board's last card, full width under the specialists: the plan it proposed, its reason
 * in full, every dissent it kept with why, or that there was none, its lists, the run's facts in one line and what it
 * cited; what must still hold before a write (with the operation keys as codes) in a data detail; its run on demand.
 */
function CoordinatorCard({
  caseId,
  run,
  result,
  kept,
  noDissent,
  portalBase,
  receiver,
  round,
}: {
  caseId: string;
  run: AgentRun;
  result: Record<string, unknown>;
  /** Each dissent kept: the specialist's name and the coordinator's reason for keeping it. */
  kept: { name: string; why: string }[];
  /** What to say when it kept none: that the specialists agreed only when three did. */
  noDissent: string;
  portalBase: string;
  receiver?: string;
  /** The sitting's number, when the board sat more than once. */
  round?: number;
}) {
  const [open, setOpen] = useState(false);
  const [recording, setRecording] = useState(false);
  const key = String(run.id ?? 'coordinator');
  const preconditions = asArray(result.preconditions).map(describeEntry);
  return (
    <MemberCard
      member="coordinator"
      name="Coordinator"
      titleId={`agent-${key}`}
      {...(round ? { 'aria-labelledby': `agent-${key} agent-${key}-round` } : {})}
      badge={
        <>
          <RoundMark id={`agent-${key}-round`} round={round} />
          <Text component="span" className="overline">
            Proposes the plan
          </Text>
        </>
      }
      meta={<RunLine run={run} portalBase={portalBase} />}
      style={{ minWidth: 0 }}
    >
      <Group gap="xs" wrap="wrap">
        <DispositionBadge disposition={String(result.disposition ?? '')} proposed />
      </Group>
      {/* Its reasoning in its own words, full of the evidence's ids: one click away in Plain (What Shutter did says
          it in plain words), open in Technical */}
      {String(result.summary ?? run.content ?? '') ? (
        <TechDetail kind="data" label="The coordinator's reasoning">
          <Text size="sm" maw="68ch">
            {String(result.summary ?? run.content ?? '')}
          </Text>
        </TechDetail>
      ) : null}
      {kept.length ? (
        kept.map((d) => (
          <Stack
            key={d.name}
            gap={2}
            p="xs"
            maw="68ch"
            style={{
              borderLeft: '3px solid var(--mantine-color-yellow-outline)',
              background: 'var(--mantine-color-body)',
              borderRadius: 'var(--mantine-radius-sm)',
            }}
          >
            <Text size="sm" fw={600}>
              {`Dissent kept: ${d.name}`}
            </Text>
            {/* What the specialist said is on its own card; the coordinator's reason for keeping it, a click away */}
            {d.why ? (
              <TechDetail
                kind="data"
                label={
                  <>
                    Why it was kept<VisuallyHidden component="span">{`, ${d.name}`}</VisuallyHidden>
                  </>
                }
              >
                <Text size="sm">{d.why}</Text>
              </TechDetail>
            ) : null}
          </Stack>
        ))
      ) : (
        <Text size="sm" c="dimmed">
          {noDissent}
        </Text>
      )}
      {/* The disagreements are the dissents kept above; the preconditions are in their own detail below */}
      <ResultLists result={result} omit={['disagreements', 'preconditions']} />
      {preconditions.length ? (
        <TechDetail kind="data" label="What the coordinator wrote must still hold">
          <Text size="sm" c="dimmed">
            The gate doesn't read these.
          </Text>
          <List size="sm" spacing={4}>
            {preconditions.map((x, i) => (
              <List.Item key={i}>
                <WithKeys text={x} />
              </List.Item>
            ))}
          </List>
        </TechDetail>
      ) : null}
      <Citations run={run} name="Coordinator" receiver={receiver} />
      <MoreToggle
        open={open}
        onToggle={() => setOpen((o) => !o)}
        controls={`agent-${key}-run`}
        describedBy={`agent-${key}`}
        label="the run"
      />
      {open ? (
        <div id={`agent-${key}-run`}>
          <Stack gap="xs">
            {/* Why the catalogue entry it cites fits, in its own words */}
            {typeof result.why === 'string' && result.why ? (
              <Text size="sm" maw="68ch">
                {result.why}
              </Text>
            ) : null}
            <RunStats run={run} />
            <ToolCalls run={run} />
          </Stack>
        </div>
      ) : (
        <div id={`agent-${key}-run`} hidden />
      )}
      <RecordingToggle
        caseId={caseId}
        run={run}
        open={recording}
        onToggle={() => setRecording((o) => !o)}
        describedBy={`agent-${key}`}
      />
    </MemberCard>
  );
}

/** The single investigator's finding, as a card: there is no board to set it beside. */
function FindingCard({
  run,
  portalBase,
  receiver,
}: {
  run: AgentRun;
  portalBase: string;
  receiver?: string;
}) {
  const key = String(run.id ?? 'generalist');
  return (
    <MemberCard
      member="generalist"
      name={nameOf(run)}
      titleId={`agent-${key}`}
      meta={<RunLine run={run} portalBase={portalBase} />}
    >
      <Group gap="xs" wrap="wrap">
        <DispositionBadge disposition={dispositionOf(run)} />
      </Group>
      <FindingDetail run={run} />
      <Citations run={run} name={nameOf(run)} receiver={receiver} />
    </MemberCard>
  );
}

/** The recorded text puts a confidence after the disposition, "resend (confidence 0.8): why", "resend (0.8): why" or
 * "resend (0.7). Why.", or the reason itself in brackets, "resend (why)". Keep the disposition and the reason, never
 * the figure. */
function keptDissent(run: AgentRun, coordinator: AgentRun | undefined): string | undefined {
  const d = asArray(asObject(coordinator?.result)?.disagreements)
    .map((x) => asObject(x) ?? {})
    .find((x) => String(x.member ?? '') === run.memberCode);
  const said = String(d?.said ?? '')
    .trim()
    .replace(/^([a-z_]+)\s*\((?:confidence\s*)?[0-9.]+%?\)\s*[:.]?\s*(?=\S)/i, '$1: ')
    .replace(/^([a-z_]+)\s*\((?:confidence\s*)?[0-9.]+%?\)\s*$/i, '$1')
    .replace(/^([a-z_]+)\s*\(([^()]+)\)$/i, '$1: $2');
  return said ? `Proposed ${said.charAt(0).toLowerCase()}${said.slice(1)}` : undefined;
}

/**
 * A specialist dissents from its own sitting's plan: the coordinator kept its disagreement, or it answered with another.
 * A result kept from a run with no answer proposes nothing, so it differs from no plan.
 */
function dissentsFrom(run: AgentRun, coordinator: AgentRun | undefined): boolean {
  if (!coordinator) return false;
  const result = asObject(coordinator.result) ?? {};
  const kept = asArray(result.disagreements).some(
    (d) => String(asObject(d)?.member ?? '') === run.memberCode,
  );
  return kept || (answered(run) && dispositionOf(run) !== String(result.disposition ?? ''));
}

/**
 * The line above a sitting's cards on a case whose board sat more than once: which sitting, the plan it reached and
 * what came of it. A later snapshot is the fact behind "collected again"; why it was needed is on the Audit trail.
 */
function RoundLine({
  id,
  round,
  of,
  latest,
}: {
  id: string;
  round: BoardRound;
  of: number;
  latest: boolean;
}) {
  const plan = String(asObject(round.coordinator?.result)?.disposition ?? '');
  return (
    <Group gap="xs" wrap="wrap" align="center">
      <Text size="sm" fw={600} id={id}>
        {`Round ${round.number} of ${of}`}
      </Text>
      {plan ? <DispositionBadge disposition={plan} proposed /> : null}
      <Text size="sm" c="dimmed">
        {!plan
          ? 'No plan yet from this round.'
          : latest
            ? 'The coordinator below proposed this plan.'
            : 'Then Shutter collected the evidence again.'}
      </Text>
    </Group>
  );
}

export function BoardPanel({
  caseId,
  open,
  mode,
  withheld = false,
  portalBase,
  receiver,
}: {
  caseId: string;
  open: boolean;
  mode: Mode;
  /** A merge or a cancel Shutter never sends: the board is not convened, whatever the mode. */
  withheld?: boolean;
  portalBase: string;
  /** The case's receiver, for the names of the evidence sections it cites. */
  receiver?: string;
}) {
  const runs = useRuns(caseId, open);
  // The investigation's runs alone: a question's runs (Ask about this case) sit on the case too
  const list = investigationRuns(runs.data);
  // Each sitting of the board on its own: a case the receiver moved under goes back to the board on new evidence
  const rounds = boardRounds(list);
  const latest = latestRound(rounds);
  const specialists = latest?.specialists ?? [];
  const coordinator = latest?.coordinator;
  const several = rounds.length > 1;
  const generalist = list.filter((r) => r.role === 'generalist').at(-1);
  // A withheld merge or cancel convenes no board in any mode, and the section says only that.
  const notConvened = withheld && list.length === 0;
  // In policy mode the board runs only for the cases the catalogue and the site's profile leave to it.
  const settledByPolicy = !notConvened && mode === 'policy' && runs.isSuccess && list.length === 0;
  const title = notConvened
    ? 'Investigation: withheld for the team'
    : mode === 'rules'
      ? 'Investigation: rules only'
      : mode === 'single'
        ? 'Investigation: one agent'
        : settledByPolicy
          ? 'Investigation: site policy'
          : 'The board';
  const board = !notConvened && !settledByPolicy && mode !== 'rules' && mode !== 'single';
  // The members that sat, once each, whichever of them answered; before any has run, the library decides how many
  const count = specialists.length;
  const note = notConvened
    ? 'Not convened: a withheld merge or cancel goes to the team that corrects it by hand, whatever the mode.'
    : mode === 'rules'
      ? 'No agents: the rules propose resending the operation unchanged at the observed version, and the gate alone decides.'
      : mode === 'single'
        ? 'One generalist agent reads the whole snapshot and proposes the plan itself.'
        : settledByPolicy
          ? "The scenario catalogue matched the case and the site's profile says who decides it. A case it leaves to the board shows the board's findings here."
          : count === 1
            ? 'One specialist agent reads the evidence; a coordinator agent proposes the plan.'
            : `${count ? `${NUMBERS[count] ?? count} specialist` : 'Specialist'} agents read the same evidence in parallel; a coordinator agent proposes one plan.`;
  const coordinatorResult = asObject(coordinator?.result) ?? {};
  const disagreements = asArray(coordinatorResult.disagreements);
  const dissent = disagreements.length;
  const planned = String(coordinatorResult.disposition ?? '');
  // Each dissent the coordinator kept, by the specialist's name, with its recorded reason for keeping it
  const keptReasons = disagreements
    .map((x) => asObject(x) ?? {})
    .map((d) => {
      const member = String(d.member ?? '');
      const run = specialists.find((r) => r.memberCode === member);
      return {
        name: run?.member?.name ?? humanize(member),
        why: String(d.why_kept ?? '') || (run ? (keptDissent(run, coordinator) ?? '') : ''),
      };
    });
  // The specialists' agreement with the plan, a dot each in member order; only three views have the evaluation's words
  const agreement = agreementOf(latest, planned);
  const views = agreement.answered.length;
  const missing = SPECIALISTS.filter((m) => !agreement.answered.some((r) => r.memberCode === m));
  const noDissent =
    agreement.word === 'unanimous'
      ? 'No disagreements to keep: the specialists agreed.'
      : agreement.word
        ? 'The coordinator kept no disagreements.'
        : `${views === 0 ? 'No specialist' : plural(views, 'specialist')} answered; the coordinator kept no disagreements.`;
  // The page's first confidence shown carries its definition
  const firstConfident = rounds
    .flatMap((r) => r.specialists)
    .find((r) => answered(r) && Number(resultOf(r).confidence ?? r.finding?.confidence) > 0);
  return (
    <Section
      id="board"
      tour="case-board"
      title={title}
      note={note}
      aside={
        coordinator ? (
          <Group gap="sm" wrap="wrap">
            {agreement.word ? (
              <AgreementDots proposed={agreement.proposed} agreement={agreement.word} />
            ) : (
              <StatusBadge
                tone="neutral"
                label={`${views === 0 ? 'No specialist' : plural(views, 'specialist')} answered`}
                hint={`${
                  missing.length
                    ? `No answer from ${missing.map((m) => memberIdentity(m).name).join(', ')}: switched off in the library, or its run gave none. `
                    : ''
                }Agreement is counted when three answer.`}
                icon={IconUsers}
              />
            )}
            {dissent ? (
              <StatusBadge
                tone="attention"
                label={`${dissent} dissent${dissent === 1 ? '' : 's'} kept`}
                hint="A specialist disagreed with the plan; the coordinator kept the disagreement in it. Dissent is not an error."
                icon={IconMessageExclamation}
              />
            ) : null}
          </Group>
        ) : null
      }
    >
      {board ? (
        <TechDetail kind="explain" label="How the board works">
          <Text size="sm" maw="68ch">
            Each member is an IRIS AI Hub agent (<CodeChip>%AI.Agent</CodeChip>), a business operation in the
            production. A confidence is the agent&apos;s own report and is not used by the gate; agreement is
            not a safety check either.
          </Text>
        </TechDetail>
      ) : null}
      {runs.isError ? <ErrorAlert error={runs.error} title="The agent runs could not be read" /> : null}
      {mode === 'rules' && !notConvened ? <NotYet>No agent runs in this mode.</NotYet> : null}
      {notConvened ? null : settledByPolicy ? (
        <NotYet>
          No agents ran: the catalogue and the site's policy settle this case, or the board hasn't been asked
          yet.
        </NotYet>
      ) : mode !== 'rules' && runs.isSuccess && list.length === 0 ? (
        <NotYet>No agent has answered yet.</NotYet>
      ) : null}
      {/* The specialists side by side, by the width the board has (beside Ask it is narrower, and no card falls
          under 240 px), then the coordinator that weighed them, full width */}
      {rounds.map((round) =>
        round.specialists.length ? (
          <Stack
            key={round.number}
            gap="xs"
            role={several ? 'group' : undefined}
            aria-labelledby={several ? `board-round-${round.number}` : undefined}
          >
            {several ? (
              <RoundLine
                id={`board-round-${round.number}`}
                round={round}
                of={rounds.length}
                latest={round === latest}
              />
            ) : null}
            <SimpleGrid
              type="container"
              cols={{ base: 1, '540px': 2, '760px': 3 }}
              spacing="sm"
              // An opened card takes a row of its own; the cards after it close the gap it leaves
              style={{ alignItems: 'start', gridAutoFlow: 'dense' }}
            >
              {round.specialists.map((r) => (
                <SpecialistCard
                  key={String(r.id ?? r.memberCode)}
                  caseId={caseId}
                  run={r}
                  portalBase={portalBase}
                  dissent={dissentsFrom(r, round.coordinator)}
                  kept={keptDissent(r, round.coordinator)}
                  receiver={receiver}
                  defineConfidence={r === firstConfident}
                  round={several ? round.number : undefined}
                />
              ))}
            </SimpleGrid>
          </Stack>
        ) : null,
      )}
      {/* When each agent worked: the pass's runs on one time axis, between the specialists and the coordinator */}
      {board ? <RunTimeline runs={list} /> : null}
      {coordinator ? (
        <CoordinatorCard
          caseId={caseId}
          run={coordinator}
          result={coordinatorResult}
          kept={keptReasons}
          noDissent={noDissent}
          portalBase={portalBase}
          receiver={receiver}
          round={several ? latest?.number : undefined}
        />
      ) : null}
      {generalist ? <FindingCard run={generalist} portalBase={portalBase} receiver={receiver} /> : null}
    </Section>
  );
}
