import type { ReactNode } from 'react';
import type { FhirReceiverSettings, SiteReceiver } from '@/api/types';
import { Term } from '@/components/Term';

/** What a receiver can take, and its FHIR block: the receiver cards' reading of an entry, which this site's guide shares. */

export interface Capability {
  yes: boolean;
  /** For the "Takes:" line. */
  short: string;
  /** For "What it cannot take": the whole meaning. */
  long: ReactNode;
}

/** What the receiver can take, as the site declared it. */
export function capabilities(r: SiteReceiver, withTerms: boolean): Capability[] {
  const f = r.features;
  // No features declared: the core assumes every one, as the downstream system's defaults
  const has = (k: string) => (f ? f[k] === true : true);
  const a = (code: string) => (withTerms ? <Term term="adt">{code}</Term> : code);
  return [
    {
      yes: has('conditional_writes'),
      short: 'conditional writes',
      long: 'Conditional writes: a write names the version it expects',
    },
    { yes: has('receipts'), short: 'receipts', long: 'Receipts: it says whether an operation was committed' },
    { yes: has('history'), short: 'history', long: 'A readable history of each encounter' },
    { yes: has('dry_run'), short: 'dry runs', long: 'Dry runs: a write rehearsed and rolled back' },
    {
      yes: r.cancels === true,
      short: 'cancels',
      long: <>Cancels ({a('A11')}, A12, A13)</>,
    },
    {
      yes: r.merges === true,
      short: 'merges',
      long: <>Merges ({a('A40')}), when the site allows them</>,
    },
  ];
}

/** The entry's fhir block when it is one the card can read, else null: a FHIR R4 receiver (DESIGN 2.1). */
export function fhirOf(r: SiteReceiver): FhirReceiverSettings | null {
  const f = r.fhir as unknown;
  return typeof f === 'object' && f !== null && !Array.isArray(f) ? (f as FhirReceiverSettings) : null;
}
