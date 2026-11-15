import type { SiteProfile, SiteReceiver } from '@/api/types';
import { ORDERS_RESULTS_BRIEF, categoryOf, historyPolicyOf } from '@/lib/categories';
import { FHIR_OVERTAKEN_LINE, KINDS, KIND_LABELS, OVERTAKEN_LINE, POLICY_SHORT } from '../profile';

/**
 * "What Shutter will do here": what a receiver's entry and the site's policy mean together, computed from the profile
 * and never typed. Every value is read as the server reads it (Shutter.Store.SiteProfile): a kind the entry does not
 * name is current state, a history policy is the entry's own, else its kind's, else the site-wide one of an older
 * profile, an approval is the policy row of the entry's tier, and declared features decide whether the gate can let a
 * write through.
 *
 * Each line has a rank, 1 when a person or a block stands in the way and 0 when not, so two readings of the same
 * receiver can be compared line by line: a change is less strict when a line's rank falls (`lessStrict`). A line with
 * no rank (a tier that is not answered yet) is compared with nothing.
 */

export type EffectId =
  | 'overtaken'
  | 'approval.single'
  | 'approval.ordered'
  | 'approval.interleaved'
  | 'case_write'
  | 'engine_resend'
  | 'mode';

export interface EffectLine {
  id: EffectId;
  /** What the line is about. */
  label: string;
  /** What Shutter does, in the page's own words. */
  text: string;
  /** 1: a person decides, or nothing is sent. 0: no person, or a send is possible. null: not answered. */
  rank: 0 | 1 | null;
}

const FEATURES = ['conditional_writes', 'receipts', 'history', 'dry_run'] as const;

const isObject = (x: unknown): x is Record<string, unknown> =>
  typeof x === 'object' && x !== null && !Array.isArray(x);

/** The entry's tier when it is one the approval table has, else "". */
const tierOf = (r: SiteReceiver): string =>
  [1, 2, 3].includes(Number(r.tier)) ? String(Number(r.tier)) : '';

/**
 * Whether the gate could let a write from a case through at this receiver, as the profile declares it: never at an
 * orders and results receiver; at a FHIR receiver only with its own switch on; with declared features only when all four
 * are true; and with neither features nor a FHIR block, on the downstream system's defaults, which declare all four.
 */
function caseWrite(r: SiteReceiver): { possible: boolean; text: string } {
  if (categoryOf(r) === 'orders_results')
    return { possible: false, text: 'No: an order or result is never resent from its case.' };
  if (isObject(r.fhir))
    return r.fhir.recovery_enabled === true
      ? { possible: true, text: 'Yes, its one update, after a person approves it.' }
      : { possible: false, text: 'No: recovery is off for this FHIR receiver.' };
  if (isObject(r.features)) {
    const f = r.features;
    return FEATURES.every((k) => f[k] === true)
      ? { possible: true, text: 'Yes, through the gate and the approvals above.' }
      : {
          possible: false,
          text: 'No: the site has not declared conditional writes, receipts, a readable history and dry runs here, so the gate blocks every write. Shutter investigates and sends nothing.',
        };
  }
  return { possible: true, text: 'Yes, through the gate and the approvals above.' };
}

/** The lines for one receiver under a profile. */
export function effectsOf(profile: SiteProfile, r: SiteReceiver): EffectLine[] {
  const category = categoryOf(r);
  const fhir = isObject(r.fhir);
  const policy = historyPolicyOf(r, profile);
  const person = fhir || category === 'orders_results' || policy === 'correct';
  const tier = tierOf(r);
  const write = caseWrite(r);
  const engine = r.engine_resend === true;
  const enabled = profile.recovery?.mode === 'enabled';
  return [
    {
      id: 'overtaken',
      label: 'An overtaken failure',
      text: fhir
        ? FHIR_OVERTAKEN_LINE
        : category === 'orders_results'
          ? ORDERS_RESULTS_BRIEF
          : OVERTAKEN_LINE[policy],
      rank: person ? 1 : 0,
    },
    ...KINDS.map((kind): EffectLine => {
      const value = tier ? (profile.policy?.[tier]?.[kind] ?? 'approval') : '';
      return {
        id: `approval.${kind}`,
        label: `A resend of ${KIND_LABELS[kind]}`,
        text: fhir
          ? 'Only a person releases it, whatever the tier.'
          : tier
            ? `Tier ${tier}: ${POLICY_SHORT[value] ?? value}.`
            : 'The tier is not answered.',
        rank: fhir ? 1 : tier ? (value === 'automatic' ? 0 : 1) : null,
      };
    }),
    {
      id: 'case_write',
      label: 'A write to it from a case',
      text: write.text,
      rank: write.possible ? 0 : 1,
    },
    {
      id: 'engine_resend',
      label: "An outage's messages",
      text: engine
        ? 'Can be sent again through the engine, after one approval.'
        : 'Not resent through the engine.',
      rank: engine ? 0 : 1,
    },
    {
      id: 'mode',
      label: 'The site',
      text: enabled
        ? 'Recovery is enabled: what the lines above allow may be sent.'
        : 'Shadow mode: Shutter investigates and sends nothing, whatever the lines above say.',
      rank: enabled ? 0 : 1,
    },
  ];
}

/**
 * The first line that is less strict in `after` than in `before`, or null: a person's approval removed, a write or an
 * engine resend made possible, an overtaken failure no longer asking a person. A line without a rank on either side is
 * not compared, and an absent `before` (the receiver is not in that profile) compares with nothing.
 */
export function lessStrict(before: EffectLine[] | null, after: EffectLine[]): EffectLine | null {
  if (!before) return null;
  for (const line of after) {
    const was = before.find((b) => b.id === line.id);
    if (!was || was.rank === null || line.rank === null) continue;
    if (line.rank < was.rank) return line;
  }
  return null;
}

/** Who approves a resend at this receiver, as one sentence for the draft pane. */
export function approvalText(profile: SiteProfile, r: SiteReceiver): string {
  if (isObject(r.fhir)) return 'Only a person releases its update, whatever the tier.';
  const tier = tierOf(r);
  if (!tier) return 'The tier is not answered, so nobody is named yet.';
  const each = KINDS.map(
    (kind) =>
      `${KIND_LABELS[kind]}, ${POLICY_SHORT[profile.policy?.[tier]?.[kind] ?? 'approval'] ?? 'one approval'}`,
  );
  return `At tier ${tier}: ${each.join('; ')}.`;
}
