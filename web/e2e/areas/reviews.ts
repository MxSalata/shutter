import type { Area } from '../helpers';

/** The production review: the list and a review. */
export const area: Area = {
  tag: '@reviews',
  screens: [
    { path: '/reviews', heading: 'Production review' },
    { path: '/reviews/PR-000001', heading: 'Review PR-000001' },
    { path: '/reviews/PR-000003', heading: 'Review PR-000003' },
  ],
  liveScreens: [{ path: '/reviews/PR-000001', heading: 'Review PR-000001' }],
  liveWordChecked: false,
};
