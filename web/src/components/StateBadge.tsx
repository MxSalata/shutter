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

/** How a case was handled: neutral, except an escalation or a call for more evidence, which need a person. */
export function DispositionBadge({ disposition }: { disposition: string }) {
  if (!disposition) return null;
  return <StatusBadge {...dispositionStatus(disposition)} variant="outline" />;
}
