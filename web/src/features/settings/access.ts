import type { AccessReport, AccessRowId } from '@/api/types';

/**
 * The words of the "Your access" section (`GET /access`, CONTRACTS 5): the columns, each row in a reader's words, which
 * installed role the signed-in user's column is, and the sentences under the table. Pure, so each is tested on its own.
 * The word "live" is not used here: the trial keeps it for the second layer.
 */

/** The columns: the roles a person signs in to Shutter with, in the table's order, with the words for each head. */
export const ACCESS_COLUMNS: ReadonlyArray<{ role: string; label: string }> = [
  { role: 'Shutter_Demo', label: 'Demo viewer' },
  { role: 'Shutter_Judge', label: 'Judge' },
  { role: 'Shutter_Operator', label: 'Operator' },
  { role: 'Shutter_Approver', label: 'Approver' },
];

/** What each row is, in the reader's words. */
export const ACCESS_ROW_WORDS: Record<AccessRowId, string> = {
  view: 'View cases, incidents, evidence and plans',
  approve: 'Approve or reject a plan',
  scenarios: 'Run the scenarios',
  reset: 'Reset the shared demo',
  liveAgents: 'Convene the board and ask new questions, which spends the model budget',
  configure: "Change the site's settings",
  inbox: "The Management Portal's Workflow inbox",
  guide: 'The Shutter in IRIS page',
  trace: "The Management Portal's Visual Trace",
  publisher: 'Read cases through the MCP publisher',
};

/** A row's words; a row this build does not know is named by its id. */
export const rowWords = (id: string): string => ACCESS_ROW_WORDS[id as AccessRowId] ?? id;

/** The label of a role's column, or the role's name for one the table has no column for. */
export const roleLabel = (role: string): string => ACCESS_COLUMNS.find((c) => c.role === role)?.label ?? role;

/**
 * The installed roles whose column is the signed-in user's, cell for cell over the rows this instance has: none for a
 * sign-in with a role of its own, and none while the roles' columns are not recorded (they would all read false).
 */
export function matchingRoles(
  report: Pick<AccessReport, 'rows' | 'read'>,
  roles: readonly string[] = ACCESS_COLUMNS.map((c) => c.role),
): string[] {
  if (report.read === 'none') return [];
  const rows = report.rows.filter((r) => r.available);
  return roles.filter((role) => rows.every((r) => !!r.roles[role] === !!r.you));
}

const list = (names: string[]): string =>
  names.length <= 1 ? (names[0] ?? '') : `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;

/** The sentence under the table about the signed-in user's own column. */
export function yourColumnSentence(report: Pick<AccessReport, 'rows' | 'read'>): string {
  if (report.read === 'none')
    return "Your column is your sign-in's own, read now. The roles' columns are not recorded on this instance yet: the production's next start records them.";
  const matching = matchingRoles(report);
  if (matching.length === 0)
    return "Your column is your sign-in's own. It matches none of the roles Shutter installs, so your sign-in has a role of its own.";
  return `Your column is your sign-in's own. It matches ${list(matching.map((r) => `${roleLabel(r)} (${r})`))}.`;
}

/**
 * The section's one line on the page's first layer, which opens the table: which installed role the user's column
 * matches, in as few words as the page's budget leaves.
 */
export function compareLine(report: Pick<AccessReport, 'rows' | 'read'>): string {
  if (report.read === 'none') return 'Each sign-in compared';
  const matching = matchingRoles(report);
  if (matching.length === 0) return 'Each sign-in compared: yours is a role of its own';
  return `Each sign-in compared: yours matches ${list(matching.map(roleLabel))}`;
}

/** What the judges' account adds to the public demo's viewer, shown while the demo is on. */
export const JUDGES_SENTENCE =
  "What the judges' account adds: the agents run for real, on new questions, a convened board and the scenarios it plays, under the day's budget; it does not reset the shared demo.";

/** The needs of a row in words: the alternatives joined with "or", each its resources with "and". */
export const needsWords = (needs: string[][]): string =>
  needs.length === 0 ? 'nothing' : needs.map((alt) => alt.join(' and ')).join(', or ');
