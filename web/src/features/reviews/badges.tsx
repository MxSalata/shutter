import { Badge, Group, Text, Tooltip } from '@mantine/core';
import type { FindingStatus, ReviewSummary, Severity } from '@/api/types';
import { humanize } from '@/lib/format';
import { CONFIDENCE_HINTS, SEVERITIES, SEVERITY_COLOURS, STATUS_LABELS } from './review';

const REVIEW_STATE: Record<string, { colour: string; hint: string }> = {
  sweeping: { colour: 'blue', hint: "Reading the production's settings, errors and failed messages" },
  ranking: {
    colour: 'violet',
    hint: 'The findings are stored; the agent is ranking them within their tiers',
  },
  done: { colour: 'green', hint: 'The review is finished' },
  failed: { colour: 'red', hint: 'The sweep failed; the reason is on the review' },
};

const AGENT_STATE: Record<string, { label: string; colour: string; hint: string }> = {
  pending: { label: 'Agent pending', colour: 'blue', hint: 'The agent has not answered yet' },
  ok: { label: 'Ranked', colour: 'teal', hint: 'The agent ranked and explained the findings' },
  no_record: {
    label: 'No recording',
    colour: 'gray',
    hint: 'No recorded explanation for this configuration: the deterministic order stands',
  },
  skipped: { label: 'Agent not asked', colour: 'gray', hint: 'The deterministic order stands' },
  schema_failed: {
    label: 'Ranking refused',
    colour: 'orange',
    hint: "The agent's ranking was not accepted: the deterministic order stands",
  },
  error: {
    label: 'Agent error',
    colour: 'red',
    hint: 'The agent did not answer: the deterministic order stands',
  },
};

export function ReviewStateBadge({ state }: { state: string }) {
  const s = REVIEW_STATE[state];
  return (
    <Tooltip label={s?.hint ?? state}>
      <Badge color={s?.colour ?? 'gray'} size="sm" tabIndex={0} style={{ textTransform: 'none' }}>
        {humanize(state)}
      </Badge>
    </Tooltip>
  );
}

export function AgentStateBadge({ state }: { state: string }) {
  const s = AGENT_STATE[state];
  return (
    <Tooltip label={s?.hint ?? state}>
      <Badge
        variant="outline"
        color={s?.colour ?? 'gray'}
        size="sm"
        tabIndex={0}
        style={{ textTransform: 'none' }}
      >
        {s?.label ?? humanize(state)}
      </Badge>
    </Tooltip>
  );
}

export function SeverityBadge({ severity }: { severity: Severity }) {
  return (
    <Badge
      color={SEVERITY_COLOURS[severity] ?? 'gray'}
      size="sm"
      variant="light"
      style={{ textTransform: 'none' }}
    >
      {humanize(severity)}
    </Badge>
  );
}

export function ConfidenceText({ confidence }: { confidence: string }) {
  return (
    <Tooltip label={CONFIDENCE_HINTS[confidence] ?? confidence}>
      <Text span size="xs" c="dimmed" tabIndex={0} style={{ textDecoration: 'underline dotted' }}>
        {humanize(confidence)}
      </Text>
    </Tooltip>
  );
}

export function StatusBadge({ status }: { status: FindingStatus }) {
  return (
    <Badge
      color={status === 'new' ? 'blue' : 'grape'}
      variant={status === 'new' ? 'light' : 'filled'}
      size="sm"
      style={{ textTransform: 'none' }}
    >
      {STATUS_LABELS[status] ?? humanize(status)}
    </Badge>
  );
}

/** "11 medium, 2 low": the tiers with findings, or "No findings"; nothing while the review is still sweeping. */
export function SeverityCounts({ summary }: { summary: ReviewSummary }) {
  if (!summary.bySeverity) return null;
  const tiers = SEVERITIES.filter((s) => (summary.bySeverity?.[s] ?? 0) > 0);
  if (!tiers.length)
    return (
      <Text size="sm" c="dimmed">
        No findings
      </Text>
    );
  return (
    <Group gap={4} wrap="wrap">
      {tiers.map((s) => (
        <Badge
          key={s}
          color={SEVERITY_COLOURS[s]}
          variant="light"
          size="sm"
          style={{ textTransform: 'none' }}
        >
          {summary.bySeverity![s]} {s}
        </Badge>
      ))}
    </Group>
  );
}
