import { List, Progress, Stack, Text } from '@mantine/core';
import type { ReviewDetail } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { Section } from '@/components/Section';
import { StatusNotice } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { formatDuration, formatInt, formatUsd, humanize } from '@/lib/format';
import { AgentStateBadge } from './badges';
import { describeAgent, explainedCount, explainedNotes } from './review';

/**
 * "2 of 9 findings explained", with a bar: the server's own counts when the agent answered, else the findings that
 * carry an explanation, so a review with no recorded explanation says 0 of 9 rather than nothing. Left out when the
 * agent was not asked or has not answered yet.
 */
function Explained({ r }: { r: ReviewDetail }) {
  if (r.state !== 'done' || !r.findings.length) return null;
  if (r.agent.state === 'skipped' || r.agent.state === 'pending') return null;
  const { explained, total } = explainedCount(r);
  const notes = [
    explainedNotes(r.agent),
    explained > 0 && explained < total
      ? 'A finding with no explanation shows the deterministic text only.'
      : '',
  ]
    .filter(Boolean)
    .join(' ');
  return (
    <Stack gap={4}>
      <Text size="sm" fw={600}>
        {`${explained} of ${total} ${total === 1 ? 'finding' : 'findings'} explained by the agent`}
      </Text>
      <Progress
        value={total ? (explained / total) * 100 : 0}
        size="sm"
        maw={420}
        aria-label={`${explained} of ${total} findings explained by the agent`}
      />
      {notes ? (
        <Text size="xs" c="dimmed">
          {notes}
        </Text>
      ) : null}
    </Stack>
  );
}

/**
 * What the agent did with the findings. A ranked review leads with the agent's own summary, then how many findings it
 * explained and what it does not decide. Without a ranking it says what the agent does on a live system and that
 * this review kept the deterministic order. What the agent sees and does, and how the run went, are one click away.
 */
export function AgentBlock({ r }: { r: ReviewDetail }) {
  const a = r.agent;
  const view = describeAgent(a, r.state);
  const ranked = a.state === 'ok';
  const needsAttention = view.tone === 'attention' || view.tone === 'blocking';
  const ran = a.mode !== null;
  return (
    <Section
      id="agent"
      tour="review-agent"
      title="The agent's ranking"
      aside={<AgentStateBadge state={a.state} />}
    >
      {needsAttention ? (
        <StatusNotice tone={view.tone} title={view.title} role="note">
          <Text size="sm">{view.text}</Text>
        </StatusNotice>
      ) : ranked ? (
        <Text fw={600}>{view.title}</Text>
      ) : (
        <Text>{view.text}</Text>
      )}
      {a.summary ? <Text>{a.summary}</Text> : null}
      <Explained r={r} />
      {a.unknowns.length ? (
        <Stack gap={2}>
          <Text size="sm" fw={600}>
            What the findings do not decide
          </Text>
          <List size="sm" spacing={2}>
            {a.unknowns.map((u) => (
              <List.Item key={u}>{u}</List.Item>
            ))}
          </List>
        </Stack>
      ) : null}
      {ranked ? (
        <Text size="sm" c="dimmed">
          {view.text}
        </Text>
      ) : null}
      <TechDetail label="What the agent sees and does" kind="explain">
        One IRIS AI Hub agent (<CodeChip>%AI.Agent</CodeChip>) ranks the findings within their severity tiers
        and explains each against the case history. It sees names, values, counts and case ids, never an
        error&apos;s text, and never changes a severity or a count.
      </TechDetail>
      {ran ? (
        <TechDetail label="How the agent ran" kind="data">
          <KeyValueList
            rows={[
              ['Mode', a.mode ? humanize(a.mode) : ''],
              ['Model', a.model ?? ''],
              [
                'Tokens',
                a.promptTokens || a.completionTokens
                  ? `${formatInt(a.promptTokens)} in · ${formatInt(a.completionTokens)} out`
                  : '',
              ],
              [
                'Cost',
                a.mode === 'replay' ? `${formatUsd(0)} (a replay spends nothing)` : formatUsd(a.costUsd),
              ],
              ['Duration', a.durationMs ? formatDuration(a.durationMs) : ''],
              ['Record key', <Digest key="k" value={a.recordKey} label="record key" length={40} />],
            ]}
          />
        </TechDetail>
      ) : null}
    </Section>
  );
}
