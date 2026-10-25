/**
 * A case's headline is a fixed opening sentence and a text the server cuts at 200 characters (the plan's summary in
 * CaseWorkflow, the team's reason in Case.CloseByHand), so a long one can stop in the middle of a word. Such a headline is shown up to its last
 * whole word, with an ellipsis; any other headline is shown as it is.
 */
const SUMMARY_LIMIT = 200;

/** The openings CaseWorkflow and Case put before a 200-character text; a rejection puts "Rejected by <user>: " first. */
const OPENINGS = [
  /^Valid message\. Do not resend: a later event moved the encounter on\. /,
  /^Resend the .+? unchanged, after rehearsal and approval\. /,
  /^Already applied at the receiver: reconcile, do not resend\. /,
  /^Escalated to a person\. /,
  /^More evidence needed\. /,
  /^New pattern, a person decides: /,
  /^Handled by the team\. /,
];

/**
 * The gate's headline, as Case writes it: "Blocked by the gate: Blocked: ordering SUPERSEDED_BY_LATER_EVENT (policy
 * 2026-10-20.1, stage proposal)". It reads as the checks that failed, in words; the codes stay on the case page.
 */
const GATE_HEADLINE = /^Blocked by the gate: Blocked: (.+?)(?: \(policy [^)]*\))?$/;

function gateHeadline(headline: string): string {
  const m = GATE_HEADLINE.exec(headline);
  if (!m) return '';
  const checks = m[1]
    .split(', ')
    .map((part) => /^([a-z_]+) [A-Z_]+$/.exec(part)?.[1])
    .filter((x): x is string => !!x)
    .map((x) => x.replace(/_/g, ' '));
  if (!checks.length) return '';
  const names = checks.length === 1 ? checks[0] : `${checks.slice(0, -1).join(', ')} and ${checks.at(-1)}`;
  return `Blocked by the gate: the ${names} check${checks.length === 1 ? '' : 's'} failed.`;
}

export function clampHeadline(headline: string | undefined | null): string {
  if (!headline) return '';
  const gate = gateHeadline(headline);
  if (gate) return gate;
  // The server cuts at a whole word itself since 20 October 2026; a cut it made before then could leave a full stop
  // or a bracket before its ellipsis.
  headline = headline.replace(/[\s.,;:(-]+…$/, '…');
  const rejected = /^Rejected by [^:]+: /.exec(headline)?.[0] ?? '';
  const rest = headline.slice(rejected.length);
  for (const opening of OPENINGS) {
    const m = opening.exec(rest);
    if (!m) continue;
    const summary = rest.slice(m[0].length);
    // Shorter than the limit: nothing was cut. Ending a sentence: the cut fell where the text ends cleanly anyway.
    if (summary.length !== SUMMARY_LIMIT || /[.!?)…]$/.test(summary)) return headline;
    // The last word may be a part of one: drop it, and any punctuation the cut leaves hanging (a full stop too, so
    // that the ellipsis doesn't follow one).
    const whole = summary.replace(/\s+\S*$/, '').replace(/[\s.,;:(-]+$/, '');
    return `${rejected}${m[0]}${whole || summary}…`;
  }
  return headline;
}
