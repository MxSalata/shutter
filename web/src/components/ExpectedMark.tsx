import { expectationOf, type ExpectedScenario, type OutcomeCase } from '@/lib/status';
import { StatusBadge } from './StatusBadge';

/**
 * How a case compares with its scenario's expectation, after its outcome badge: "As expected" (positive), "Stopped by
 * the gate" (neutral) or "Not as expected" (blocking), each with the scenario's expectation as its tooltip; nothing
 * where no expectation applies.
 */
export function ExpectedMark({ c, scenario }: { c: OutcomeCase; scenario?: ExpectedScenario | null }) {
  const e = expectationOf(c, scenario);
  if (e.kind === 'unknown') return null;
  const words = {
    'as-expected': 'As expected',
    stopped: 'Stopped by the gate',
    differs: 'Not as expected',
  } as const;
  const tone = { 'as-expected': 'positive', stopped: 'neutral', differs: 'blocking' } as const;
  return (
    <StatusBadge
      tone={tone[e.kind]}
      label={words[e.kind]}
      hint={e.kind === 'as-expected' ? `${scenario?.id} expects ${e.expects}` : e.label}
      variant="outline"
    />
  );
}
