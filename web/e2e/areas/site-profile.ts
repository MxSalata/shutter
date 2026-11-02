import type { Area } from '../helpers';

/** The Site profile page with a change a case's What-if card suggested, pre-filled: the address names the case and the fact. */
export const SUGGESTION = '/site-profile?suggest=C-000008&fact=W1';

/**
 * The Site profile, in Plain and in Technical. The suggested change leaves the draft different from the saved version,
 * so it is also the screen with the save bar showing: the layout run checks it at 360 px with the bar up.
 */
export const area: Area = {
  tag: '@site-profile',
  screens: [
    { path: '/site-profile', heading: 'Site profile' },
    { path: SUGGESTION, heading: 'Site profile', name: 'Site profile (a suggested change)' },
    { path: '/site-profile', heading: 'Site profile', detail: 'technical' },
    {
      path: SUGGESTION,
      heading: 'Site profile',
      name: 'Site profile (a suggested change)',
      detail: 'technical',
    },
  ],
  liveScreens: [{ path: SUGGESTION, heading: 'Site profile', name: 'Site profile (a suggested change)' }],
  liveWordChecked: true,
};
