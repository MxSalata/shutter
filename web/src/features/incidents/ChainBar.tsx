import { CHAIN_STATES } from './describe';

/**
 * One 8 px segment per chain, in its state's tone: the shape of an incident at a glance, beside the words that say it
 * ("8 cases in 6 chains", the outcome badge). Decoration only, so it is hidden from assistive technology.
 */
export function ChainBar({ states }: { states: string[] }) {
  if (!states.length) return null;
  return (
    <span className="chain-bar" aria-hidden>
      {states.map((state, i) => (
        <span key={i} data-tone={CHAIN_STATES[state]?.tone ?? 'neutral'} />
      ))}
    </span>
  );
}
