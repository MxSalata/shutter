import type { SiteProfile, SiteReceiver } from '@/api/types';
import { categoryOf, historyPolicyOf } from '@/lib/categories';
import { fhirOf } from '@/features/site-profile/receiverCapabilities';
import type { AtReceiver, AutomaticHold, CatalogueEntry } from '@/features/site-guide/model';

/**
 * For the trial's mock only: GET /catalogue's atReceivers (CONTRACTS 6.8) for the trial's own site profile, which a
 * visitor may change and save in the browser. A port of Shutter.Catalogue.Matcher.AtReceiver, with its Settle, WhenHolds
 * and ReceiverFacts. The page never computes this: it shows what the route answered. The port is held to the real
 * route by atReceivers.test.ts: on the profile recorded with the route's answer (catalogue-recorded.json) it gives the
 * recorded rows exactly.
 */

type Facts = Record<string, string>;

/** Matcher.ReceiverFacts: the receiver's history policy and category; the case's facts empty. */
export function receiverFacts(r: SiteReceiver | undefined, profile: SiteProfile): Facts {
  return {
    other_source: '',
    history_policy: historyPolicyOf(r, profile),
    receiver_category: categoryOf(r),
    occupant_case: '',
  };
}

/** A profile flag as Shutter.Util.Json.Str reads it. */
function flagOf(profile: SiteProfile, flag: string): string {
  const v = (profile as unknown as Record<string, unknown>)[flag];
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return v ? '1' : '0';
  return '';
}

/** Matcher.WhenHolds. */
function whenHolds(when: string, facts: Facts, profile: SiteProfile): boolean {
  const w = when.trim();
  if (w === '' || w === 'always') return true;
  const at = w.indexOf(':');
  const flag = (at < 0 ? w : w.slice(0, at)).trim();
  let value = (at < 0 ? '' : w.slice(at + 1)).trim();
  if (value === 'other_source') value = facts.other_source ?? '';
  if (value === '') return false;
  if (typeof facts[flag] === 'string') return facts[flag] === value;
  return flagOf(profile, flag) === value;
}

interface Settled {
  decides: string;
  outcome: string;
  outcomeRef: string;
}

/** Matcher.Settle for one match. */
function settle(entry: CatalogueEntry, facts: Facts, profile: SiteProfile): Settled {
  const decides = ['policy', 'board', 'person'].includes(entry.decides) ? entry.decides : 'board';
  let outcome = entry.preferred?.outcome ?? '';
  let outcomeRef = 'preferred';
  for (const [n, alt] of (Array.isArray(entry.alternatives) ? entry.alternatives : []).entries()) {
    if (!alt || typeof alt !== 'object') continue;
    const when = (alt.when ?? '').trim();
    if (when === '' || when === 'always' || !when.includes(':')) continue;
    if (whenHolds(when, facts, profile)) {
      outcome = alt.outcome;
      outcomeRef = `alternative:${n + 1}`;
      break;
    }
  }
  return { decides, outcome, outcomeRef };
}

/** Matcher.AtReceiver: the row for one shipped entry at one receiver of the profile. */
export function atReceiver(entry: CatalogueEntry, r: SiteReceiver, profile: SiteProfile): AtReceiver {
  const facts = receiverFacts(r, profile);
  const base = settle(entry, facts, profile);
  const row: AtReceiver = {
    receiver: r.name,
    kind: fhirOf(r) ? 'fhir_r4' : '',
    category: categoryOf(r),
    ...base,
    whenOtherSource: [],
  };
  const seen = new Set<string>();
  for (const alt of Array.isArray(entry.alternatives) ? entry.alternatives : []) {
    if (!alt || typeof alt !== 'object') continue;
    const when = (alt.when ?? '').trim();
    if (!when.includes(':')) continue;
    const flag = when.slice(0, when.indexOf(':')).trim();
    if (when.slice(when.indexOf(':') + 1).trim() !== 'other_source') continue;
    const named = typeof facts[flag] === 'string' ? facts[flag] : flagOf(profile, flag);
    if (!named || seen.has(named)) continue;
    seen.add(named);
    const on = settle(entry, { ...receiverFacts(r, profile), other_source: named }, profile);
    if (on.outcome === base.outcome && on.outcomeRef === base.outcomeRef) continue;
    row.whenOtherSource.push({ flag, otherSource: named, ...on });
  }
  return row;
}

/** The rows of every receiver of the profile with a name, in its order (SiteProfile.ReceiverNames). */
export function atReceiversOf(entry: CatalogueEntry, profile: SiteProfile): AtReceiver[] {
  return profile.receivers
    .filter((r) => typeof r.name === 'string' && r.name !== '')
    .map((r) => atReceiver(entry, r, profile));
}

/**
 * What an automatic release still sends to a person under a profile: a port of the core's
 * Shutter.Process.CaseWorkflow.AutomaticHolds, word for word, which atReceivers.test.ts holds to the recording. The
 * trial answers as a demo instance does, so another visit's movement stops there unless the profile says show.
 */
export function automaticHoldsOf(profile: SiteProfile): AutomaticHold[] {
  const fm = (profile as unknown as { further_messages?: Record<string, unknown> }).further_messages ?? {};
  const feed = (profile as unknown as { feed?: Record<string, unknown> }).feed ?? {};
  const out: AutomaticHold[] = [];
  if ((fm.admission_not_found ?? 'person') === 'person')
    out.push({
      hold: 'admission_not_found',
      when: "the receiver answers that it has no record of the patient's admission (further_messages.admission_not_found: person)",
      source: 'AdmissionOnNotFound',
    });
  if ((fm.in_patient_movement ?? 'stop') === 'show')
    out.push({
      hold: 'shown_visit',
      when: "the case shows the patient's movement on another visit (further_messages.in_patient_movement: show)",
      source: 'ShownVisit',
    });
  out.push({
    hold: 'site_entry',
    when: "one of this site's own entries stopped the case before",
    source: 'StoredSiteEntry',
  });
  out.push({
    hold: 'further_release',
    when: "a person released a stop on the case's further messages",
    source: 'FurtherReleaseJSON',
  });
  if (feed.prove_origin !== false)
    out.push({
      hold: 'origin',
      when: "the case's source cannot be proved (feed.prove_origin)",
      source: 'Shutter.Operation.Origin',
    });
  return out;
}
