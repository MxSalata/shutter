import {
  Accordion,
  Badge,
  Button,
  Card,
  Group,
  List,
  Progress,
  SimpleGrid,
  Stack,
  Text,
  Title,
} from '@mantine/core';
import { IconChevronDown, IconMessageExclamation, IconUsers } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { useRuns, useSettings } from '@/api/hooks';
import type { AgentRun, Mode } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { JsonBlock } from '@/components/JsonBlock';
import { costAtPrice } from '@/lib/cost';
import { asArray, asObject } from '@/lib/json';
import { formatDuration, formatInt, formatUsd, humanize, keyLabel } from '@/lib/format';
import { PROVENANCE } from '@/lib/status';
import { describeEntry } from './derive';
import { showEvidence } from './evidenceLinks';
import { NotYet, Section } from './Section';

/** Small counts in words, as the board's note says them. */
const NUMBERS: Record<number, string> = { 1: 'One', 2: 'Two', 3: 'Three', 4: 'Four', 5: 'Five' };

const LISTS: [string, string][] = [
  ['violations', 'Violations'],
  ['superseding_evidence', 'Superseding evidence'],
  ['affected_systems', 'Affected systems'],
  ['unknowns', 'Unknown'],
  ['preconditions', 'Preconditions'],
  ['disagreements', 'Disagreements kept'],
];

function RunStats({ run, portalBase }: { run: AgentRun; portalBase: string }) {
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
      {run.ensMessageId ? (
        <PortalLink
          href={
            run.messageLink ||
            `${portalBase}EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(run.ensMessageId)}`
          }
          what={`message ${run.ensMessageId}, the agent's request and answer`}
          size="xs"
        >
          The run's message in the production
        </PortalLink>
      ) : null}
      {run.error ? (
        <Text size="xs" c="red">
          {run.error}
        </Text>
      ) : null}
    </Stack>
  );
}

function ResultLists({ result }: { result: Record<string, unknown> }) {
  return (
    <>
      {LISTS.map(([key, label]) => {
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

function EvidenceRefs({ refs }: { refs: unknown }) {
  const list = asArray(refs).map(describeEntry);
  if (!list.length) return null;
  return (
    <Group gap={4} wrap="wrap">
      <Text size="xs" c="dimmed">
        Cites
      </Text>
      {list.map((r, i) => (
        <Badge
          key={`${i}:${r}`}
          size="xs"
          variant="outline"
          color="gray"
          component="button"
          type="button"
          onClick={() => showEvidence(r)}
          style={{ textTransform: 'none', cursor: 'pointer' }}
        >
          {keyLabel(r)}
        </Badge>
      ))}
    </Group>
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

/** A specialist's own confidence in its finding: shown second, and never read by the gate. */
function confidenceText(confidence: number): string {
  return Number.isFinite(confidence) && confidence > 0
    ? `Confidence ${Math.round(confidence * 100)}%, self-reported; not used by the gate`
    : '';
}

/** The details of a member's finding: its reasoning, what it cites, its run and its tool calls. */
function FindingDetail({
  run,
  portalBase,
  withConfidence = true,
}: {
  run: AgentRun;
  portalBase: string;
  /** False where the card already shows the confidence. */
  withConfidence?: boolean;
}) {
  const result = asObject(run.finding?.findings) ?? asObject(run.result) ?? {};
  const confidence = withConfidence
    ? confidenceText(Number(result.confidence ?? run.finding?.confidence))
    : '';
  return (
    <Stack gap="xs">
      {run.member?.perspective ? (
        <Text size="xs" c="dimmed">
          {run.member.perspective}
        </Text>
      ) : null}
      <Text size="sm">{String(result.summary ?? run.finding?.summary ?? run.content ?? '')}</Text>
      {confidence ? (
        <Text size="xs" c="dimmed">
          {confidence}
        </Text>
      ) : null}
      <ResultLists result={result} />
      <EvidenceRefs refs={result.evidence_refs} />
      <RunStats run={run} portalBase={portalBase} />
      <ToolCalls run={run} />
    </Stack>
  );
}

/** A finding's disposition, from its structured result or the stored finding. */
function dispositionOf(run: AgentRun): string {
  const result = asObject(run.finding?.findings) ?? asObject(run.result) ?? {};
  return String(result.disposition ?? run.finding?.disposition ?? '');
}

/** A card's small label over its name: what the agent is on the board. */
function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <Text size="xs" fw={700} tt="uppercase" c="dimmed" style={{ letterSpacing: '0.04em' }}>
      {children}
    </Text>
  );
}

/** A toggle for the rest of a card, the finding or the reasoning in full, named for the card it sits in. */
function MoreToggle({
  open,
  onToggle,
  controls,
  describedBy,
  label,
}: {
  open: boolean;
  onToggle: () => void;
  controls: string;
  describedBy: string;
  label: string;
}) {
  return (
    <Group>
      <Button
        size="compact-xs"
        variant="subtle"
        onClick={onToggle}
        aria-expanded={open}
        aria-controls={controls}
        aria-describedby={describedBy}
        leftSection={
          <IconChevronDown
            size={14}
            aria-hidden
            style={{ transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
          />
        }
      >
        {open ? `Hide ${label}` : `Show ${label}`}
      </Button>
    </Group>
  );
}

/** The border of a card that dissented: two pixels in the attention tone, beside the badge that says it in words. */
const DISSENT_BORDER = { borderColor: 'var(--mantine-color-yellow-outline)', borderWidth: 2 };

/**
 * A specialist as a card: its name, what it proposed, its own confidence (marked as its own, never the gate's) and its
 * reason in a few lines, with the whole finding on demand. A specialist that disagreed with the plan carries the
 * Dissent badge and the dissent as the coordinator kept it, so dissent is read, not hidden.
 */
function SpecialistCard({
  run,
  portalBase,
  dissent,
  kept,
}: {
  run: AgentRun;
  portalBase: string;
  dissent: boolean;
  /** The dissent as the coordinator kept it, in a line: what the specialist proposed and why. */
  kept?: string;
}) {
  const [open, setOpen] = useState(false);
  const result = asObject(run.finding?.findings) ?? asObject(run.result) ?? {};
  const key = String(run.id ?? run.memberCode);
  const name = run.member?.name ?? humanize(run.memberCode);
  const confidence = Number(result.confidence ?? run.finding?.confidence);
  const shown = Number.isFinite(confidence) && confidence > 0;
  return (
    <Card
      component="article"
      aria-labelledby={`agent-${key}`}
      withBorder
      padding="sm"
      style={{ minWidth: 0, ...(dissent ? DISSENT_BORDER : {}) }}
    >
      <Stack gap={6}>
        <Group justify="space-between" gap={6} wrap="wrap">
          <Eyebrow>Specialist</Eyebrow>
          {dissent ? (
            <StatusBadge tone="attention" size="xs" label="Dissent" icon={IconMessageExclamation} />
          ) : null}
        </Group>
        <Title order={3} fz="sm" id={`agent-${key}`}>
          {name}
        </Title>
        <DispositionBadge disposition={dispositionOf(run)} proposed />
        {shown ? (
          <Stack gap={2}>
            <Text size="xs" c="dimmed">
              {`Confidence ${Math.round(confidence * 100)}%, self-reported`}
            </Text>
            {/* The bar only repeats the figure, in grey: no tone, since the gate does not read it */}
            <Progress value={Math.round(confidence * 100)} color="gray" size="xs" aria-hidden />
          </Stack>
        ) : null}
        {kept ? <Text size="sm">{kept}</Text> : null}
        {/* The reason in a few lines; opened, the finding gives it whole */}
        {open ? null : (
          <Text size="sm" c="dimmed" lineClamp={4}>
            {String(result.summary ?? run.finding?.summary ?? run.content ?? '')}
          </Text>
        )}
        <MoreToggle
          open={open}
          onToggle={() => setOpen((o) => !o)}
          controls={`agent-${key}-finding`}
          describedBy={`agent-${key}`}
          label="the finding"
        />
        {open ? (
          <div id={`agent-${key}-finding`}>
            <FindingDetail run={run} portalBase={portalBase} withConfidence={false} />
          </div>
        ) : (
          <div id={`agent-${key}-finding`} hidden />
        )}
      </Stack>
    </Card>
  );
}

/**
 * The coordinator as the board's last card: the plan it proposed, its reason, and every dissent it kept with why, or
 * that there was none; its lists and its run on demand.
 */
function CoordinatorCard({
  run,
  result,
  kept,
  portalBase,
}: {
  run: AgentRun;
  result: Record<string, unknown>;
  /** Each dissent kept: the specialist's name and the coordinator's reason for keeping it. */
  kept: { name: string; why: string }[];
  portalBase: string;
}) {
  const [open, setOpen] = useState(false);
  const key = String(run.id ?? 'coordinator');
  return (
    <Card
      component="article"
      aria-labelledby={`agent-${key}`}
      withBorder
      padding="sm"
      bg="var(--mantine-color-default-hover)"
      style={{ minWidth: 0 }}
    >
      <Stack gap={6}>
        <Eyebrow>Proposes the plan</Eyebrow>
        <Title order={3} fz="sm" id={`agent-${key}`}>
          Coordinator
        </Title>
        <DispositionBadge disposition={String(result.disposition ?? '')} proposed />
        <Text size="sm" lineClamp={open ? undefined : 5}>
          {String(result.summary ?? run.content ?? '')}
        </Text>
        {kept.length ? (
          kept.map((d) => (
            <Stack
              key={d.name}
              gap={2}
              p="xs"
              style={{
                borderLeft: '3px solid var(--mantine-color-yellow-outline)',
                background: 'var(--mantine-color-body)',
                borderRadius: 'var(--mantine-radius-sm)',
              }}
            >
              <Text size="sm" fw={600}>
                {`Dissent kept: ${d.name}`}
              </Text>
              {d.why ? <Text size="sm">{d.why}</Text> : null}
            </Stack>
          ))
        ) : (
          <Text size="xs" c="dimmed">
            No disagreements to keep: the specialists agreed.
          </Text>
        )}
        <MoreToggle
          open={open}
          onToggle={() => setOpen((o) => !o)}
          controls={`agent-${key}-finding`}
          describedBy={`agent-${key}`}
          label="the reasoning"
        />
        {open ? (
          <Stack id={`agent-${key}-finding`} gap="xs">
            <ResultLists result={result} />
            <RunStats run={run} portalBase={portalBase} />
          </Stack>
        ) : (
          <div id={`agent-${key}-finding`} hidden />
        )}
      </Stack>
    </Card>
  );
}

/** The single investigator's finding, as a card: there is no board to set it beside. */
function FindingCard({ run, portalBase }: { run: AgentRun; portalBase: string }) {
  return (
    <Card padding="sm" withBorder>
      <Stack gap="xs">
        <DispositionBadge disposition={dispositionOf(run)} />
        <Text fw={600}>{run.member?.name ?? humanize(run.memberCode)}</Text>
        <FindingDetail run={run} portalBase={portalBase} />
      </Stack>
    </Card>
  );
}

export function BoardPanel({
  caseId,
  open,
  mode,
  withheld = false,
  portalBase,
}: {
  caseId: string;
  open: boolean;
  mode: Mode;
  /** A merge or a cancel Shutter never sends: the board is not convened, whatever the mode. */
  withheld?: boolean;
  portalBase: string;
}) {
  const runs = useRuns(caseId, open);
  const list = runs.data ?? [];
  const specialists = list.filter((r) => r.role === 'specialist');
  const coordinator = list.filter((r) => r.role === 'coordinator').at(-1);
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
  const note = notConvened
    ? 'Not convened: a withheld merge or cancel goes to the team that corrects it by hand, whatever the mode.'
    : mode === 'rules'
      ? 'No agents: the rules propose resending the operation unchanged at the observed version, and the gate alone decides.'
      : mode === 'single'
        ? 'One generalist agent reads the whole snapshot and proposes the plan itself.'
        : settledByPolicy
          ? "The scenario catalogue matched the case and the site's profile says who decides it. A case it leaves to the board shows the board's findings here."
          : `${specialists.length ? `${NUMBERS[specialists.length] ?? specialists.length} specialists` : 'The specialists'} read the same evidence in parallel, each from one perspective, and cite what they used. The coordinator keeps their disagreements and proposes one plan. A confidence is the agent's own report and is not used by the gate; agreement is not a safety check either.`;
  const coordinatorResult = asObject(coordinator?.result) ?? {};
  const disagreements = asArray(coordinatorResult.disagreements);
  const dissent = disagreements.length;
  // A specialist dissents when the coordinator kept its disagreement, or when it proposed another disposition
  const dissenters = new Set(disagreements.map((d) => String(asObject(d)?.member ?? '')));
  const dissents = (r: AgentRun) =>
    !!coordinator &&
    (dissenters.has(r.memberCode) ||
      (!!dispositionOf(r) && dispositionOf(r) !== String(coordinatorResult.disposition ?? '')));
  // The dissent's reason as the coordinator recorded it, without the specialist's self-reported confidence
  const keptDissent = (r: AgentRun) => {
    const d = disagreements
      .map((x) => asObject(x) ?? {})
      .find((x) => String(x.member ?? '') === r.memberCode);
    // The recorded text puts a confidence after the disposition, "resend (confidence 0.8): why" or
    // "resend (0.8): why", or the reason itself in brackets, "resend (why)". Keep the disposition and
    // the reason, never the figure.
    const said = String(d?.said ?? '')
      .trim()
      .replace(/^([a-z_]+)\s*\((?:confidence\s*)?[0-9.]+%?\)/i, '$1')
      .replace(/^([a-z_]+)\s*\(([^()]+)\)$/i, '$1: $2');
    return said ? `Proposed ${said.charAt(0).toLowerCase()}${said.slice(1)}` : undefined;
  };
  // Each dissent the coordinator kept, by the specialist's name, with its recorded reason for keeping it
  const keptReasons = disagreements
    .map((x) => asObject(x) ?? {})
    .map((d) => {
      const member = String(d.member ?? '');
      const run = specialists.find((r) => r.memberCode === member);
      return {
        name: run?.member?.name ?? humanize(member),
        why: String(d.why_kept ?? '') || (run ? (keptDissent(run) ?? '') : ''),
      };
    });
  return (
    <Section
      id="board"
      tour="case-board"
      title={title}
      note={note}
      aside={
        coordinator ? (
          dissent ? (
            <StatusBadge
              tone="attention"
              label={`${dissent} dissent${dissent === 1 ? '' : 's'} kept`}
              hint="A specialist disagreed with the plan; the coordinator kept the disagreement in it. Dissent is not an error."
              icon={IconMessageExclamation}
            />
          ) : (
            <StatusBadge
              tone="neutral"
              label="Unanimous"
              hint="The specialists agreed; agreement is not a safety check, the gate is"
              icon={IconUsers}
            />
          )
        ) : null
      }
    >
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
      {/* The specialists, then the coordinator that weighed them: on a laptop four cards side by side */}
      {specialists.length || coordinator ? (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 4 }} spacing="sm">
          {specialists.map((r) => (
            <SpecialistCard
              key={String(r.id ?? r.memberCode)}
              run={r}
              portalBase={portalBase}
              dissent={dissents(r)}
              kept={keptDissent(r)}
            />
          ))}
          {coordinator ? (
            <CoordinatorCard
              run={coordinator}
              result={coordinatorResult}
              kept={keptReasons}
              portalBase={portalBase}
            />
          ) : null}
        </SimpleGrid>
      ) : null}
      {generalist ? <FindingCard run={generalist} portalBase={portalBase} /> : null}
    </Section>
  );
}
