/**
 * A citation (a board card's chip for a cited section, a "Cites" badge in Ask) opens the cited evidence on the same
 * page. Under the hash router a `#evidence-…` link would be read as a route (and land on the not-found page), so the
 * citations call showEvidence with the evidence ref they name (`message`, `validation`, ..., or `catalogue:E7`): the
 * case page switches to its Evidence tab, and the Evidence panel scrolls that section to the top under the tab bar,
 * opens what it recorded, and moves focus to the section's heading.
 */
export const SHOW_EVIDENCE = 'shutter:show-evidence';

export function showEvidence(kind: string) {
  window.dispatchEvent(new CustomEvent<string>(SHOW_EVIDENCE, { detail: kind }));
}
