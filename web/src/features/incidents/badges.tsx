import { IconArrowsRight, IconArrowsShuffle, IconPoint, type Icon } from '@tabler/icons-react';
import type { ChainItem } from '@/api/types';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { humanize } from '@/lib/format';
import {
  CHAIN_STATES,
  INCIDENT_STATES,
  ITEM_STATES,
  itemOutcome,
  KIND_HINTS,
  type Meaning,
} from './describe';

type Size = 'xs' | 'sm' | 'md' | 'lg';

function MeaningBadge({ meaning, value, size = 'sm' }: { meaning: Meaning; value: string; size?: Size }) {
  const status = meaning[value] ?? { tone: 'neutral' as const, label: humanize(value), hint: value };
  return <StatusBadge {...status} size={size} />;
}

export const IncidentStateBadge = (p: { state: string; size?: Size }) => (
  <MeaningBadge meaning={INCIDENT_STATES} value={p.state} size={p.size} />
);
export const ChainStateBadge = (p: { state: string; size?: Size }) => (
  <MeaningBadge meaning={CHAIN_STATES} value={p.state} size={p.size} />
);
export const ItemStateBadge = (p: { state: string; size?: Size }) => (
  <MeaningBadge meaning={ITEM_STATES} value={p.state} size={p.size} />
);

/**
 * What came of an operation: its case's outcome ("Delivered, verified", "Nothing to send, verified", "Blocked") once
 * the case has run, and the operation's own state ("Pending", "Stopped") before that or when it never ran (N14).
 */
export function OperationBadge({ item, size }: { item: ChainItem; size?: Size }) {
  const outcome = itemOutcome(item);
  return outcome ? (
    <OutcomeBadge c={outcome} size={size} />
  ) : (
    <ItemStateBadge state={item.state} size={size} />
  );
}

const KIND_ICONS: Record<string, Icon> = {
  single: IconPoint,
  ordered: IconArrowsRight,
  interleaved: IconArrowsShuffle,
};

/** How the chain's failures relate: a fact about it, not a status, so neutral, with an icon of its own. */
export function KindBadge({ kind }: { kind: string }) {
  if (!kind) return null;
  return (
    <StatusBadge
      tone="neutral"
      label={humanize(kind)}
      hint={KIND_HINTS[kind] ?? kind}
      icon={KIND_ICONS[kind] ?? null}
      variant="outline"
    />
  );
}
