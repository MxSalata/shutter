import { Badge } from '@mantine/core';
import { IconBroadcast, IconTestPipe } from '@tabler/icons-react';
import { TRIAL } from '@/env/mode';

/**
 * Where a confirmed action takes effect, beside the confirm dialog's title: "Trial only" in a trial page (grape) and
 * "Live system" in a live one (an outline in the text colour, no status colour). Only confirms of an action with an
 * effect outside the browser carry it, so it never becomes noise. The live chip matters as much: the dangerous mistake
 * is a person who thinks they are in the trial while approving a real write.
 */
export function EnvChip() {
  if (TRIAL)
    return (
      <Badge
        color="grape"
        variant="light"
        size="sm"
        leftSection={<IconTestPipe size={12} aria-hidden />}
        style={{ textTransform: 'none' }}
      >
        Trial only
      </Badge>
    );
  return (
    <Badge
      color="gray"
      variant="outline"
      size="sm"
      leftSection={<IconBroadcast size={12} aria-hidden />}
      style={{ textTransform: 'none', color: 'var(--mantine-color-text)', borderColor: 'currentColor' }}
    >
      Live system
    </Badge>
  );
}
