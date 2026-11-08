/**
 * The held-out fair test's figures, as docs/readme/fair-test.md gives them: twelve sealed cases, written by an author who
 * had not read the catalogue, played three times each against release 1.0.0's code. Typed here so the Evaluation page
 * can show them beside the board's own recorded scores, and checked against the document by heldOut.test.ts, so a
 * figure the document changes fails the test rather than going stale here.
 */
export const HELD_OUT = {
  /** The sealed cases, F01 to F12. */
  cases: 12,
  /** The runs of each case in each mode. */
  repeats: 3,
  /** The release whose code the cases were played against. */
  release: '1.0.0',
  /** Strict mean loss per mode (lower is better), as the results table prints it. */
  board: '0.167',
  /** The single investigator, as the page settles the two disputed F08 runs. */
  single: '0.167',
  /** Site policy, played with no key: no model call. */
  policy: '3.500',
  /** The case Site policy, with no model, wrote wrongly in all three runs (Wx): the transfer the source had cancelled. */
  wroteWrongly: 'F09',
  url: 'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md',
} as const;
