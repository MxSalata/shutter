import { Group, Text, Tooltip } from '@mantine/core';
import {
  IconAlertCircle,
  IconCircleCheck,
  IconCircleOff,
  IconClock,
  IconListDetails,
  IconNote,
  IconProgress,
  type Icon,
} from '@tabler/icons-react';
import type { FindingStatus, ReviewSummary, Severity } from '@/api/types';
import { StatusBadge } from '@/components/StatusBadge';
import { humanize } from '@/lib/format';
import { SEVERITY_STATUS } from '@/lib/status';
import type { Status } from '@/lib/tone';
import { CONFIDENCE_HINTS, SEVERITIES, STATUS_LABELS } from './review';

const REVIEW_STATE: Record<string, Status> = {
  sweeping: {
    tone: 'info',
    label: 'Sweeping',
    hint: "Reading the production's settings, errors and failed messages",
    icon: IconProgress,
  },
  ranking: {
    tone: 'info',
    label: 'Ranking',
    hint: 'The findings are stored; the agent is ranking them within their tiers',
    icon: IconProgress,
  },
  done: { tone: 'neutral', label: 'Done', hint: 'The review is finished', icon: IconCircleCheck },
  failed: {
    tone: 'blocking',
    label: 'Failed',
    hint: 'The sweep failed; the reason is on the review',
    icon: IconAlertCircle,
  },
};

const AGENT_STATE: Record<string, Status> = {
  pending: { tone: 'info', label: 'Agent pending', hint: 'The agent has not answered yet', icon: IconClock },
  ok: {
    tone: 'neutral',
    label: 'Ranked',
    hint: 'The agent ranked and explained the findings',
    icon: IconListDetails,
  },
  no_record: {
    tone: 'neutral',
    label: 'No recording',
    hint: 'No recorded explanation for this configuration: the deterministic order stands',
  },
  skipped: { tone: 'neutral', label: 'Agent not asked', hint: 'The deterministic order stands' },
  schema_failed: {
    tone: 'attention',
    label: 'Ranking refused',
    hint: "The agent's ranking was not accepted: the deterministic order stands",
  },
  error: {
    tone: 'blocking',
    label: 'Agent error',
    hint: 'The agent did not answer: the deterministic order stands',
  },
};

export function ReviewStateBadge({ state }: { state: string }) {
  return (
    <StatusBadge {...(REVIEW_STATE[state] ?? { tone: 'neutral', label: humanize(state), hint: state })} />
  );
}

export function AgentStateBadge({ state }: { state: string }) {
  return (
    <StatusBadge
      {...(AGENT_STATE[state] ?? { tone: 'neutral', label: humanize(state), hint: state })}
      variant="outline"
    />
  );
}

export function SeverityBadge({ severity }: { severity: Severity }) {
  return <StatusBadge {...(SEVERITY_STATUS[severity] ?? { tone: 'neutral', label: humanize(severity) })} />;
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

/** The annotation states are all neutral: a new finding is an outline, a marked one is a light badge with its own icon. */
const STATUS_ICONS: Partial<Record<FindingStatus, Icon>> = {
  intended: IconNote,
  accepted_risk: IconNote,
  false_positive: IconCircleOff,
};

export function FindingStatusBadge({ status }: { status: FindingStatus }) {
  return (
    <StatusBadge
      tone="neutral"
      label={STATUS_LABELS[status] ?? humanize(status)}
      icon={STATUS_ICONS[status] ?? null}
      variant={status === 'new' ? 'outline' : 'light'}
    />
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
        <StatusBadge key={s} {...SEVERITY_STATUS[s]} label={`${summary.bySeverity![s]} ${s}`} />
      ))}
    </Group>
  );
}
