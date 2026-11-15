/**
 * What the trial's stop does: its mock records the stop but plays an approval's recording all the same, while on IRIS
 * a plan can't be approved and no new recovery call is admitted. Said beside the stop on Settings, and its first sentence in the banner, until the mock
 * enforces it. A module of its own, so the banner on every page does not pull in the Settings page.
 */
export const TRIAL_STOP_RECORDED =
  'In the trial the stop is recorded but not enforced: approving a case still plays its recording.';

export const TRIAL_STOP = `${TRIAL_STOP_RECORDED} On IRIS a plan can't be approved while recovery is stopped, and no new recovery call is admitted.`;
