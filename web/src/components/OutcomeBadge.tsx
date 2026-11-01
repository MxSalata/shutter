import type { BadgeProps } from '@mantine/core';
import { caseOutcome, type ExpectedScenario, type OutcomeCase } from '@/lib/status';
import { StatusBadge } from './StatusBadge';

/**
 * What came of a case (lib/status.ts caseOutcome): the list's short words with the long form as the tooltip, or the
 * long form on the case page.
 */
export function OutcomeBadge({
  c,
  scenario,
  form = 'short',
  size,
}: {
  c: OutcomeCase;
  scenario?: ExpectedScenario | null;
  form?: 'short' | 'long';
  size?: BadgeProps['size'];
}) {
  const o = caseOutcome(c, scenario);
  const label = form === 'short' ? o.short : o.label;
  const hint = form === 'short' && o.label !== o.short ? o.label : o.hint;
  return (
    <StatusBadge
      tone={o.tone}
      label={label}
      hint={hint}
      icon={o.icon}
      size={size as 'xs' | 'sm' | 'md' | 'lg' | 'xl' | undefined}
    />
  );
}
