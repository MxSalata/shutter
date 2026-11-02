import type { Area } from '../helpers';

/** The Agent library. */
export const area: Area = {
  tag: '@library',
  screens: [
    { path: '/library', heading: 'Agent library' },
    // Each card's class, item, collection and tool, and the page's expert line, open
    { path: '/library', heading: 'Agent library', detail: 'technical' },
  ],
  liveScreens: [{ path: '/library', heading: 'Agent library' }],
  liveWordChecked: true,
};
