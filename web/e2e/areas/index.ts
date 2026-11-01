import type { Area } from '../helpers';
import { area as case_ } from './case';
import { area as caseEvidence } from './case-evidence';
import { area as cases } from './cases';
import { area as evaluation } from './evaluation';
import { area as health } from './health';
import { area as incidents } from './incidents';
import { area as library } from './library';
import { area as reviews } from './reviews';
import { area as scenarios } from './scenarios';
import { area as settings } from './settings';
import { area as shell } from './shell';
import { area as signIn } from './sign-in';
import { area as siteProfile } from './site-profile';

/**
 * Every area of the app, in the navigation's order after the shell and the sign-in page. Each area file belongs to
 * the page package that owns the area; the shared runs (accessibility, layout, the live hospital's axe run) iterate
 * over this list and tag each test with its area, so `--grep @<area>` runs one area's share of them.
 */
export const areas: Area[] = [
  shell,
  signIn,
  scenarios,
  cases,
  case_,
  caseEvidence,
  incidents,
  reviews,
  siteProfile,
  library,
  settings,
  evaluation,
  health,
];

/** The areas the shared runs name in their own tests, beside the screens. */
export { caseEvidence, shell, signIn, siteProfile };
