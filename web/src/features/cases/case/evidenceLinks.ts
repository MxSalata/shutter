/**
 * A finding's "Cites" badges open the cited evidence on the same page. Under the hash router a
 * `#evidence-…` link would be read as a route (and land on the not-found page), so the badges call
 * showEvidence and the evidence panel opens, scrolls to and focuses the items of that kind.
 */
export const SHOW_EVIDENCE = 'interlock:show-evidence';

export function showEvidence(kind: string) {
  window.dispatchEvent(new CustomEvent<string>(SHOW_EVIDENCE, { detail: kind }));
}
