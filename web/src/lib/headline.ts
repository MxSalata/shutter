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

export function clampHeadline(headline: string | undefined | null): string {
  if (!headline) return '';
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
