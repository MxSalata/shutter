import { caseState, CASE_STATES, disposition as dispositionStatus } from '@/lib/status';
import { TONE_COLOURS } from '@/lib/tone';
import { StatusBadge } from './StatusBadge';

/** The case states the list filters by, in workflow order. */
export const CASE_STATE_NAMES = Object.keys(CASE_STATES);

/** A state's Mantine colour, for a timeline bullet: the colour of its tone. */
export const stateColour = (state: string) => TONE_COLOURS[caseState(state).tone];

/** A case's workflow state: information while it runs, attention when a person is needed, blocking when stopped. */
export function StateBadge({ state, size = 'sm' }: { state: string; size?: 'xs' | 'sm' | 'md' | 'lg' }) {
  return <StatusBadge {...caseState(state)} size={size} />;
}

/** The dispositions a plan proposes; a hand correction or an abandoned case is what happened, not a proposal. */
const PROPOSALS = new Set(['resend', 'reconcile', 'superseded', 'more_evidence', 'escalate']);

/**
 * How a case was handled: neutral, except an escalation or a call for more evidence, which need a person. With
 * `proposed`, a proposal reads as one ("Proposed: Resend"), so beside a Blocked state it is not read as advice.
 */
export function DispositionBadge({
  disposition,
  proposed = false,
}: {
  disposition: string;
  proposed?: boolean;
}) {
  if (!disposition) return null;
  const status = dispositionStatus(disposition);
  const label = proposed && PROPOSALS.has(disposition) ? `Proposed: ${status.label}` : status.label;
  return <StatusBadge {...status} label={label} variant="outline" />;
}
