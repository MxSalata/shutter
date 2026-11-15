/**
 * What the trial's stop does: its mock records the stop but plays an approval's recording all the same, while IRIS
 * refuses Shutter's recovery calls. Said beside the stop on Settings, and its first sentence in the banner, until the mock
 * enforces it. A module of its own, so the banner on every page does not pull in the Settings page.
 */
export const TRIAL_STOP_RECORDED =
  'In the trial the stop is recorded but not enforced: approving a case still plays its recording.';

export const TRIAL_STOP = `${TRIAL_STOP_RECORDED} On IRIS it refuses Shutter’s recovery calls, so an approved write is not sent.`;
