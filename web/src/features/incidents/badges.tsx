import { Badge, Tooltip } from '@mantine/core';
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
  const [colour, hint] = meaning[value] ?? ['gray', value];
  return (
    <Tooltip label={hint} multiline maw={320}>
      <Badge color={colour} size={size} tabIndex={0} style={{ textTransform: 'none' }}>
        {humanize(value)}
      </Badge>
    </Tooltip>
  );
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

export function KindBadge({ kind }: { kind: string }) {
  if (!kind) return null;
  return (
    <Tooltip label={KIND_HINTS[kind] ?? kind} multiline maw={320}>
      <Badge variant="outline" color="gray" tabIndex={0} style={{ textTransform: 'none' }}>
        {humanize(kind)}
      </Badge>
    </Tooltip>
  );
}
