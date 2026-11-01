import type { Area } from '../helpers';

/** The Site profile page with a change a case's What-if card suggested, pre-filled: the address names the case and the fact. */
export const SUGGESTION = '/site-profile?suggest=C-000008&fact=W1';

/** The Site profile. */
export const area: Area = {
  tag: '@site-profile',
  screens: [
    { path: '/site-profile', heading: 'Site profile' },
    { path: SUGGESTION, heading: 'Site profile', name: 'Site profile (a suggested change)' },
  ],
  liveScreens: [{ path: SUGGESTION, heading: 'Site profile', name: 'Site profile (a suggested change)' }],
  liveWordChecked: false,
};
