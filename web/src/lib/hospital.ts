/**
 * The demo hospital's name, shown wherever the product names it to a visitor: the live banner, the trial's words and
 * the guide. Chosen to read as plainly fictional; its patients are made up too.
 */
export const HOSPITAL_NAME = "Mikolaj's Fictional Hospital";

/** What the online demo's Management Portal asks for first, in the words every link to it shares. */
export const PORTAL_SIGN_IN = 'GitHub or an emailed code';

/**
 * The trial's recorded S8 case in Board mode (src/mocks/fixtures.json): the board escalating the case a gate cannot catch.
 * The live hospital's banner links to it for a visitor who cannot convene the board live (decided on 3 Nov 2026: the
 * demo's own rotation convenes no board, to keep its model budget for the judges).
 */
export const TRIAL_BOARD_CASE = 'C-000008';

/**
 * How often the live hospital's player sends a new failure, as the banner and the live sign-in page say it: "a new
 * failure every 7 minutes", "every minute", or the unnumbered form when the server gave no interval.
 */
export function failureCadence(every: number | undefined): string {
  if (!every || every < 1) return 'a new failure every few minutes';
  return every === 1 ? 'a new failure every minute' : `a new failure every ${every} minutes`;
}
