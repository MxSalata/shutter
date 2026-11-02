import type { Area } from '../helpers';

/** Settings and costs. */
export const area: Area = {
  tag: '@settings',
  screens: [
    { path: '/settings', heading: 'Settings and costs' },
    // The production items' classes and settings, what the instance lacks, the cases' table and the API's JSON, open
    { path: '/settings', heading: 'Settings and costs', detail: 'technical' },
  ],
  liveWordChecked: true,
};
