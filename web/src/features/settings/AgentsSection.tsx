import { Group, Stack, Text } from '@mantine/core';
import { CodeChip } from '@/components/CodeChip';
import { MemberAvatar } from '@/components/MemberAvatar';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { Term } from '@/components/Term';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import type { AgentItem, Settings } from '@/api/types';
import { formatInt, humanize } from '@/lib/format';
import { PROOF } from '@/lib/proof';
import {
  agentsSentence,
  answeringBadge,
  answeringOf,
  itemBadge,
  memberOfItem,
  replayFacts,
} from './settingsText';

/**
 * Every answer replays a run recorded with the real agents on IRIS AI Hub (build 154), with claude-opus-5-5, so it
 * needs no model provider here (F3, N7). The build and the models come from the evaluation the runs were recorded
 * for, never typed; a piece the evaluation cannot give is left out.
 */
function ReplayIntro() {
  const { build, models } = replayFacts(PROOF);
  return (
    <Text data-testid="agents-intro">
      Every answer <Term term="replay">replays</Term> a run recorded with the real agents on IRIS AI Hub
      {build ? ` (build ${build})` : ''}
      {models.length ? (
        <>
          , with{' '}
          {models.map((m, i) => (
            <span key={m}>
              {i > 0 ? (i === models.length - 1 ? ' and ' : ', ') : ''}
              <CodeChip>{m}</CodeChip>
            </span>
          ))}
        </>
      ) : null}
      , so it needs no model provider here.
    </Text>
  );
}

type DetailColumn = {
  key: 'model' | 'providerConfig' | 'answeredBy' | 'maxIterations' | 'tokenBudget';
  label: string;
};
const DETAIL_COLUMNS: DetailColumn[] = [
  { key: 'model', label: 'Model' },
  { key: 'providerConfig', label: 'Provider' },
  { key: 'answeredBy', label: 'Answered by' },
  { key: 'maxIterations', label: 'Iterations' },
  { key: 'tokenBudget', label: 'Token budget' },
];

/** The mode as set, and what it resolved to when that differs: "Auto (replay)". */
function modeAsSet(a: AgentItem): string {
  if (!a.mode) return 'not set';
  return a.effectiveMode && a.effectiveMode !== a.mode
    ? `${humanize(a.mode)} (${a.effectiveMode})`
    : humanize(a.mode);
}

const hasValue = (v: unknown) => v !== undefined && v !== '';

/**
 * The agent items as the production holds them: class, mode as configured, and the settings some item has (a replaying
 * item has no model or limits). Under the API mimic, "Answered by" is on the first layer already and is not repeated.
 */
function ItemSettings({ items, mimic }: { items: AgentItem[]; mimic: boolean }) {
  const columns = DETAIL_COLUMNS.filter(
    (c) => !(mimic && c.key === 'answeredBy') && items.some((a) => hasValue(a[c.key])),
  );
  return (
    <StackTable aria-label="Settings of the agent items" className="stack-table">
      <StackTable.Thead>
        <StackTable.Tr>
          <StackTable.Th>Production item</StackTable.Th>
          <StackTable.Th>Mode as set</StackTable.Th>
          {columns.map((c) => (
            <StackTable.Th key={c.key}>{c.label}</StackTable.Th>
          ))}
        </StackTable.Tr>
      </StackTable.Thead>
      <StackTable.Tbody>
        {items.map((a) => (
          <StackTable.Tr key={a.name}>
            <StackTable.Td data-label="Production item">
              <Text size="sm" fw={500}>
                {a.name}
                {a.enabled === false ? ' (disabled)' : ''}
              </Text>
              {a.agentClass ? <CodeChip>{a.agentClass}</CodeChip> : null}
            </StackTable.Td>
            <StackTable.Td data-label="Mode as set">{modeAsSet(a)}</StackTable.Td>
            {columns.map((c) => {
              const v = a[c.key];
              return (
                <StackTable.Td key={c.key} data-label={c.label}>
                  {!hasValue(v) ? (
                    'not set'
                  ) : c.key === 'tokenBudget' ? (
                    formatInt(v)
                  ) : c.key === 'model' ? (
                    <CodeChip>{String(v)}</CodeChip>
                  ) : (
                    String(v)
                  )}
                </StackTable.Td>
              );
            })}
          </StackTable.Tr>
        ))}
      </StackTable.Tbody>
    </StackTable>
  );
}

/** What the instance lacks, in one line: a replay needs none of it, so it is detail, not the section's opening. */
function absences(s: Settings, replaying: boolean): string | null {
  const missing = [
    !s.aiHubPresent && 'AI Hub',
    !s.liveRunnerPresent && 'the AI Hub runner',
    s.providerConfigured === false && 'a model provider',
  ].filter(Boolean) as string[];
  if (!missing.length) return null;
  return `Not on this instance: ${missing.join(', ')}.${replaying ? ' A replay needs none of them.' : ''}`;
}

/**
 * The Agents section: what the instance has, first. How the agents answer in one badge and one sentence, then each
 * production item that runs an agent with its board member's mark and its mode; the production's own settings, what
 * the instance lacks and how the modes work are one click away.
 */
export function AgentsSection({ s }: { s: Settings }) {
  const { kind } = answeringOf(s);
  const badge = answeringBadge(kind);
  const mimic = kind === 'mimic';
  const replaying = kind === 'replay';
  const none = absences(s, replaying);
  const items = s.agentItems;
  return (
    <Section
      id="settings-agents"
      title="Agents"
      tour="settings-agents"
      aside={badge ? <StatusBadge {...badge} size="md" /> : undefined}
    >
      {replaying ? (
        <ReplayIntro />
      ) : (
        <Text fw={600} data-testid="agents-intro">
          {agentsSentence(s)}
        </Text>
      )}
      <StackTable aria-label="Production items that run an agent" className="stack-table stack-cards">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th>Agent</StackTable.Th>
            <StackTable.Th>How it answers</StackTable.Th>
            <StackTable.Th>Production item</StackTable.Th>
            {mimic ? <StackTable.Th>Answered by</StackTable.Th> : null}
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {items.map((a) => {
            const member = memberOfItem(a);
            return (
              <StackTable.Tr key={a.name}>
                <StackTable.Td data-label="Agent">
                  <Group gap="xs" wrap="nowrap">
                    <MemberAvatar member={member.code} />
                    <Text size="sm" fw={500}>
                      {member.name}
                    </Text>
                  </Group>
                </StackTable.Td>
                <StackTable.Td data-label="How it answers">
                  <StatusBadge {...itemBadge(a, !!s.mock)} />
                </StackTable.Td>
                <StackTable.Td data-label="Production item" className="stack-meta" data-label-hidden>
                  {a.name}
                </StackTable.Td>
                {mimic ? (
                  <StackTable.Td data-label="Answered by">
                    <Text size="sm">{a.answeredBy ?? ''}</Text>
                  </StackTable.Td>
                ) : null}
              </StackTable.Tr>
            );
          })}
        </StackTable.Tbody>
      </StackTable>
      <TechDetail label="Classes, modes, models and budgets" kind="data">
        <Stack gap="xs">
          {none ? <Text size="sm">{none}</Text> : null}
          {s.mock ? (
            <Text size="sm">
              No model answers while the mimic is on; the runs are labelled mock and cost nothing.
            </Text>
          ) : null}
          <ItemSettings items={items} mimic={mimic} />
        </Stack>
      </TechDetail>
      <TechDetail label="How the modes work" kind="explain">
        <Stack gap="xs">
          <Text size="sm">
            Each item runs its agent live, records a live run, or replays a recording; auto runs live when a
            model provider is configured and replays otherwise. A replay answers with the recorded run for a
            scenario&apos;s case. A case with no recording, such as one from an HL7 file of your own, takes
            the rules path instead: the gate alone decides, and a resend still waits for a person&apos;s
            approval.
          </Text>
          <Text size="sm">
            The last scenario run or a reset sets the investigation mode, and live failures are investigated
            in it too.
          </Text>
        </Stack>
      </TechDetail>
      <Group gap="xs" wrap="wrap" align="baseline">
        <Text size="sm">Investigation mode for new cases: {humanize(s.mode)}</Text>
        {s.scenario ? <Text size="sm">· Last scenario: {s.scenario}</Text> : null}
        {s.resetAt ? (
          <Group gap={4} wrap="nowrap" align="baseline">
            <Text size="sm">· Last reset</Text>
            <Timestamp iso={s.resetAt} />
          </Group>
        ) : null}
      </Group>
    </Section>
  );
}
