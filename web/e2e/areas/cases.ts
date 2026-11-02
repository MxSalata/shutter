import type { Area } from '../helpers';

/** The Cases list. */
export const area: Area = {
  tag: '@cases',
  screens: [
    { path: '/cases', heading: 'Cases' },
    // The failure's codes beside each row
    { path: '/cases', heading: 'Cases', detail: 'technical' },
    // One scenario's cases, as the Scenarios page links to it
    { path: '/cases?scenario=S8', heading: 'Cases' },
  ],
  liveWordChecked: true,
};
