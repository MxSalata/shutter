import { StatusBadge } from '@/components/StatusBadge';
import { humanize } from '@/lib/format';
import { CHAIN_STATES, INCIDENT_STATES, ITEM_STATES, KIND_HINTS, type Meaning } from './describe';

function MeaningBadge({
  meaning,
  value,
  size = 'sm',
}: {
  meaning: Meaning;
  value: string;
  size?: 'xs' | 'sm' | 'md' | 'lg';
}) {
  const status = meaning[value] ?? { tone: 'neutral' as const, label: humanize(value), hint: value };
  return <StatusBadge {...status} size={size} />;
}

export const IncidentStateBadge = (p: { state: string; size?: 'xs' | 'sm' | 'md' | 'lg' }) => (
  <MeaningBadge meaning={INCIDENT_STATES} value={p.state} size={p.size} />
);
export const ChainStateBadge = (p: { state: string; size?: 'xs' | 'sm' | 'md' | 'lg' }) => (
  <MeaningBadge meaning={CHAIN_STATES} value={p.state} size={p.size} />
);
export const ItemStateBadge = (p: { state: string; size?: 'xs' | 'sm' | 'md' | 'lg' }) => (
  <MeaningBadge meaning={ITEM_STATES} value={p.state} size={p.size} />
);

/** How the chain's failures relate: a fact about it, not a status, so neutral and without an icon. */
export function KindBadge({ kind }: { kind: string }) {
  if (!kind) return null;
  return (
    <StatusBadge
      tone="neutral"
      label={humanize(kind)}
      hint={KIND_HINTS[kind] ?? kind}
      icon={null}
      variant="outline"
    />
  );
}
