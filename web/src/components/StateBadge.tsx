import type { CSSProperties } from 'react';
import type { ReceiverKind } from '@/api/types';
import { caseState, CASE_STATES, disposition as dispositionStatus, FHIR_RESEND } from '@/lib/status';
import { TONE_COLOURS } from '@/lib/tone';
import { dispositionSlug, hasDispositionColour } from '@/theme';
import { StatusBadge } from './StatusBadge';

/** The case states the list filters by, in workflow order. */
export const CASE_STATE_NAMES = Object.keys(CASE_STATES);

/** A state's Mantine colour, for a timeline bullet: the colour of its tone. */
export const stateColour = (state: string) => TONE_COLOURS[caseState(state).tone];

/** A case's workflow state: information while it runs, attention when a person is needed, blocking when stopped. */
export function StateBadge({
  state,
  size = 'sm',
  focusable,
}: {
  state: string;
  size?: 'xs' | 'sm' | 'md' | 'lg';
  focusable?: boolean;
}) {
  return <StatusBadge {...caseState(state)} size={size} focusable={focusable} />;
}

/** The dispositions a plan proposes; a hand correction or an abandoned case is what happened, not a proposal. */
const PROPOSALS = new Set(['resend', 'reconcile', 'superseded', 'more_evidence', 'escalate']);

/**
 * The custom properties the `disposition-badge` rule in styles.css draws a known disposition with: its colour in the
 * palette of theme.ts, per colour scheme and contrast through the `--shutter-disposition-*` variables App.tsx sets.
 */
function dispositionStyle(disposition: string): CSSProperties | undefined {
  if (!hasDispositionColour(disposition)) return undefined;
  const stem = `--shutter-disposition-${dispositionSlug(disposition)}`;
  return {
    ['--disposition-fg' as string]: `var(${stem}-fg)`,
    ['--disposition-bg' as string]: `var(${stem}-bg)`,
    ['--disposition-bd' as string]: `var(${stem}-bd)`,
  };
}

/**
 * How a case was handled, or what a plan proposes: its icon, its word and its colour in the disposition palette
 * (theme.ts), the same wherever it appears, so the action reads at a glance. The word and the icon always stand with
 * the colour, which is never the only cue; a disposition the palette does not know stays a neutral outline. With
 * `proposed`, a proposal reads as one ("Proposed: Resend"), so beside a Blocked state it is not read as advice.
 */
export function DispositionBadge({
  disposition,
  proposed = false,
  focusable,
  kind,
}: {
  disposition: string;
  proposed?: boolean;
  focusable?: boolean;
  /** The case's receiver kind: a FHIR case's resend is its one version-aware update. */
  kind?: ReceiverKind;
}) {
  if (!disposition) return null;
  const status =
    kind === 'fhir_r4' && disposition === 'resend' ? FHIR_RESEND : dispositionStatus(disposition);
  const label = proposed && PROPOSALS.has(disposition) ? `Proposed: ${status.label}` : status.label;
  const style = dispositionStyle(disposition);
  return (
    <StatusBadge
      {...status}
      label={label}
      variant="outline"
      focusable={focusable}
      className={style ? 'disposition-badge' : undefined}
      style={style}
      attributes={{ 'data-disposition': style ? dispositionSlug(disposition) : undefined }}
    />
  );
}
