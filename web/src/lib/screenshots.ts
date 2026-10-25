/**
 * Pictures of the Management Portal for the demo, which has no instance to link to: each one shows what a portal link
 * would open for a case of its scenario and mode.
 */
export interface Screenshot {
  src: string;
  alt: string;
  caption: string;
}

const S8_BOARD: Screenshot = {
  src: `${import.meta.env.BASE_URL}s8-visual-trace.png`,
  alt: 'The Visual Trace of an S8 case in board mode',
  caption:
    "The Visual Trace of an S8 case in board mode, taken on a test instance on 25 October 2026 (session 20873): the failed delivery to Downstream Out, the case workflow, the evidence collector, the three specialists and the coordinator, each in its own lane, then the gate. The demo's recording has its own session numbers.",
};

/** The portal's picture for a case's Visual Trace, when there is one for its scenario and mode. */
export function traceScreenshot(c: { scenario?: string; mode?: string }): Screenshot | undefined {
  return c.scenario === 'S8' && c.mode === 'board' ? S8_BOARD : undefined;
}
