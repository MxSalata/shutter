import type { Area } from '../helpers';

/**
 * The sign-in page. It is not a screen of a signed-in session, so `screens` stays empty: the accessibility and layout
 * runs open the trial's sign-in page themselves (their "sign-in page" tests), and `trial.spec.ts` audits the live
 * sign-in page (the proof panel and the trial card) in every appearance on the build IRIS serves.
 */
export const area: Area = {
  tag: '@sign-in',
  screens: [],
  irisScreens: [],
  liveWordChecked: true,
};
