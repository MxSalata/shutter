import type { Area } from '../helpers';

/**
 * The API reference, a Technical page: the routes closed, and one open to its tables and curl line. The document quotes
 * the server's own words for the live hospital's routes, so the trial's live-word check does not apply to it.
 */
export const area: Area = {
  tag: '@api',
  screens: [
    { path: '/api', heading: 'API reference', detail: 'technical' },
    { path: '/api?op=caseApprove', heading: 'API reference', detail: 'technical', name: 'API reference, a route open' },
  ],
  liveWordChecked: false,
};
