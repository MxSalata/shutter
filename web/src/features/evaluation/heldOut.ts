/**
 * The held-out fair test's figures, as docs/readme/fair-test.md gives them: twelve sealed cases, written by an author who
 * had not read the catalogue, played three times each against release 1.0.0's code, and again on later releases. Typed
 * here so the Evaluation page can show them beside the board's own recorded scores, each with its release, and checked
 * against the document and the run records by heldOut.test.ts, so a figure they change fails the test rather than going
 * stale here.
 */
export const HELD_OUT = {
  /** The sealed cases, F01 to F12. */
  cases: 12,
  /** The runs of each case in each mode. */
  repeats: 3,
  /** The runs of each mode the card names, as the results tables count them (12 cases, 3 runs each). */
  runs: 36,
  /** The release whose code the cases were played against. */
  release: '1.0.0',
  /** Strict mean loss per mode (lower is better), as the results table prints it. */
  board: '0.167',
  /** The single investigator, as the page settles the two disputed F08 runs. */
  single: '0.167',
  /** The single investigator as `grade.py` graded it, before those two runs were settled. */
  singleGraded: '0.500',
  /** The case whose runs were disputed: graded F twice for the single investigator, settled as right. */
  disputed: 'F08',
  /** Site policy, played with no key: no model call. */
  policy: '3.500',
  /** Always escalating, the baseline the sealed rule ranks every mode against (computed, no runs). */
  escalate: '1.250',
  /** The case Site policy, with no model, wrote wrongly in all three runs (Wx): the transfer the source had cancelled. */
  wroteWrongly: 'F09',
  url: 'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md',
  /**
   * The board played again on release 1.1.1's code, as the document's "Release 1.1.x" section gives it: the same
   * proposals, and the 1.1.0 gate also held two right plans, so its strict mean as graded is worse than 1.0.0's.
   */
  v111: {
    release: '1.1.1',
    boardGraded: '0.667',
    held: ['F03', 'F07'],
    url: 'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md#release-11x',
  },
  /**
   * The latest rerun, as the document's "Release 1.4.3" section gives it: all twelve cases again, three runs each in
   * each mode, on release 1.4.3's code. A regression rerun on cases that have influenced fixes since 1.0.0, not a new
   * held-out test.
   */
  r143: {
    release: '1.4.3',
    board: '0.167',
    /** The single investigator with its F08 runs settled as on 1.0.0, and as `grade.py` graded them. */
    single: '0.167',
    singleGraded: '0.667',
    rules: '4.000',
    /** Wrong writes executed (Wx) in every row of the section's table: none, in any mode. */
    wrongWrites: 0,
    url: 'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test.md#release-143-all-12-cases-rerun',
    /**
     * One case of that rerun where the same gate, with nothing exempted, met two proposals: the agent modes proposed a
     * reconcile, which it passed, and Rules only a resend, which it blocked. Read from the run records
     * (fair-test/results-r143-all.json): evaluation evidence, not a scenario the app can run, and not S3.
     */
    sameGate: {
      case: 'F03',
      /** What the case tests, as the document's per-case table words it. */
      what: 'Committed, and the patient has moved on',
      /** The runs of the case in each mode; every one ended the same way. */
      runs: 3,
      /** The board and the single investigator alike. */
      agents: { proposal: 'reconcile', state: 'resolved' },
      rules: {
        proposal: 'resend',
        state: 'blocked',
        codes: ['ALREADY_COMMITTED', 'SUPERSEDED_BY_LATER_EVENT'],
      },
      /** Writes to the receiver, in any run of any of the three modes. */
      writes: 0,
      url: 'https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/results-r143-all.json',
    },
  },
} as const;
