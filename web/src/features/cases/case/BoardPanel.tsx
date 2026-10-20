import { Accordion, Badge, Card, Group, List, SimpleGrid, Stack, Text, Tooltip } from '@mantine/core';
import { useRuns, useSettings } from '@/api/hooks';
import type { AgentRun, Mode } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge } from '@/components/StateBadge';
import { JsonBlock } from '@/components/JsonBlock';
import { costAtPrice } from '@/lib/cost';
import { asArray, asObject } from '@/lib/json';
import { formatDuration, formatInt, formatUsd, humanize, keyLabel } from '@/lib/format';
import { describeEntry } from './derive';
import { showEvidence } from './evidenceLinks';
import { NotYet, Section } from './Section';

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
        <Tooltip
          label={
            replay
              ? `Replayed from a recorded live run${run.model ? ` on ${run.model}` : ''}: no model was called now`
              : `A live run on ${run.model}`
          }
          multiline
          maw={300}
        >
          <Badge
            size="xs"
            color={replay ? 'gray' : 'indigo'}
            variant="light"
            style={{ textTransform: 'none' }}
            tabIndex={0}
          >
            {replay ? `Recorded run${run.model ? ` · ${run.model}` : ''}, replayed` : `Live · ${run.model}`}
          </Badge>
        </Tooltip>
        {run.status !== 'ok' ? (
          <Badge size="xs" color="red" style={{ textTransform: 'none' }}>
            {humanize(run.status)}
          </Badge>
        ) : null}
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

function FindingCard({ run, portalBase }: { run: AgentRun; portalBase: string }) {
  const result = asObject(run.finding?.findings) ?? asObject(run.result) ?? {};
  const confidence = Number(result.confidence ?? run.finding?.confidence);
  return (
    <Card padding="sm" withBorder>
      <Stack gap="xs">
        <Stack gap={0}>
          <Text fw={600}>{run.member?.name ?? humanize(run.memberCode)}</Text>
          {run.member?.perspective ? (
            <Text size="xs" c="dimmed" lineClamp={3}>
              {run.member.perspective}
            </Text>
          ) : null}
        </Stack>
        <Group gap={6}>
          <DispositionBadge disposition={String(result.disposition ?? run.finding?.disposition ?? '')} />
          {Number.isFinite(confidence) && confidence > 0 ? (
            <Tooltip label="The agent's own confidence in its finding: not a measured probability">
              <Badge size="sm" variant="light" color="gray" tabIndex={0} style={{ textTransform: 'none' }}>
                confidence {Math.round(confidence * 100)}%
              </Badge>
            </Tooltip>
          ) : null}
        </Group>
        <Text size="sm">{String(result.summary ?? run.finding?.summary ?? run.content ?? '')}</Text>
        <ResultLists result={result} />
        <EvidenceRefs refs={result.evidence_refs} />
        <RunStats run={run} portalBase={portalBase} />
        <ToolCalls run={run} />
      </Stack>
    </Card>
  );
}

export function BoardPanel({
  caseId,
  open,
  mode,
  portalBase,
}: {
  caseId: string;
  open: boolean;
  mode: Mode;
  portalBase: string;
}) {
  const runs = useRuns(caseId, open);
  const list = runs.data ?? [];
  const specialists = list.filter((r) => r.role === 'specialist');
  const coordinator = list.filter((r) => r.role === 'coordinator').at(-1);
  const generalist = list.filter((r) => r.role === 'generalist').at(-1);
  // In policy mode the board runs only for the cases the catalogue and the site's profile leave to it.
  const settledByPolicy = mode === 'policy' && runs.isSuccess && list.length === 0;
  const title =
    mode === 'rules'
      ? 'Investigation: rules only'
      : mode === 'single'
        ? 'Investigation: one agent'
        : settledByPolicy
          ? 'Investigation: site policy'
          : 'The board';
  const note =
    mode === 'rules'
      ? 'No agents: the rules propose resending the operation unchanged at the observed version, and the gate alone decides.'
      : mode === 'single'
        ? 'One generalist agent reads the whole snapshot and proposes the plan itself.'
        : settledByPolicy
          ? "The scenario catalogue matched the case and the site's profile says who decides it. A case it leaves to the board shows the board's findings here."
          : 'Three specialists read the same evidence in parallel, each from one perspective, and cite what they used. The coordinator keeps their disagreements and proposes one plan.';
  return (
    <Section id="board" title={title} note={note}>
      {runs.isError ? <ErrorAlert error={runs.error} title="The agent runs could not be read" /> : null}
      {mode === 'rules' ? <NotYet>No agent runs in this mode.</NotYet> : null}
      {settledByPolicy ? (
        <NotYet>
          No agents ran: the catalogue and the site's policy settle this case, or the board hasn't been asked
          yet.
        </NotYet>
      ) : mode !== 'rules' && runs.isSuccess && list.length === 0 ? (
        <NotYet>No agent has answered yet.</NotYet>
      ) : null}
      {specialists.length ? (
        <SimpleGrid
          cols={{ base: 1, sm: Math.min(2, specialists.length), lg: Math.min(3, specialists.length) }}
          spacing="sm"
        >
          {specialists.map((r, i) => (
            <FindingCard key={String(r.id ?? i)} run={r} portalBase={portalBase} />
          ))}
        </SimpleGrid>
      ) : null}
      {generalist ? <FindingCard run={generalist} portalBase={portalBase} /> : null}
      {coordinator ? (
        <Card padding="sm" withBorder bg="var(--mantine-color-default-hover)">
          <Stack gap="xs">
            <Text fw={600}>Coordinator</Text>
            <Text size="sm">
              {String(asObject(coordinator.result)?.summary ?? coordinator.content ?? '')}
            </Text>
            <ResultLists result={asObject(coordinator.result) ?? {}} />
            {!asArray(asObject(coordinator.result)?.disagreements).length ? (
              <Text size="xs" c="dimmed">
                No disagreements to keep: the specialists agreed.
              </Text>
            ) : null}
            <RunStats run={coordinator} portalBase={portalBase} />
          </Stack>
        </Card>
      ) : null}
    </Section>
  );
}
