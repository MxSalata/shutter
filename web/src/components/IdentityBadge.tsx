import { Badge, type BadgeProps } from '@mantine/core';
import type { ReactNode } from 'react';
import { hueVar, type Hue } from '@/lib/hues';

/**
 * Which thing it is, in words with an 8 px dot in its identity hue: a run mode (Board violet, Site policy teal), a
 * board member, a role. A neutral outline badge; the dot is decoration, the words say it. (Mantine's own dot variant
 * draws from its palette, not the validated hue tokens.)
 */
export function IdentityBadge({
  hue,
  children,
  size = 'sm',
}: {
  hue: Hue;
  children: ReactNode;
  size?: BadgeProps['size'];
}) {
  return (
    <Badge
      variant="outline"
      color="gray"
      size={size}
      style={{ textTransform: 'none', color: 'var(--mantine-color-text)' }}
      leftSection={
        <span className="identity-dot" style={{ ['--mark-hue' as string]: hueVar(hue) }} aria-hidden />
      }
    >
      {children}
    </Badge>
  );
}
