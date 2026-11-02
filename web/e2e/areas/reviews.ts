import type { Area } from '../helpers';

/** The production review: the list and a review, in Plain and in Technical, and a review with one finding open. */
export const area: Area = {
  tag: '@reviews',
  screens: [
    { path: '/reviews', heading: 'Production review' },
    { path: '/reviews/PR-000001', heading: 'Review PR-000001' },
    { path: '/reviews/PR-000003', heading: 'Review PR-000003' },
    {
      path: '/reviews/PR-000001?finding=F4',
      heading: 'Review PR-000001',
      name: 'Review PR-000001 with a finding open',
    },
    { path: '/reviews', heading: 'Production review', detail: 'technical' },
    { path: '/reviews/PR-000001', heading: 'Review PR-000001', detail: 'technical' },
    {
      path: '/reviews/PR-000001?finding=F4',
      heading: 'Review PR-000001',
      name: 'Review PR-000001 with a finding open',
      detail: 'technical',
    },
  ],
  liveScreens: [{ path: '/reviews/PR-000001', heading: 'Review PR-000001' }],
  liveWordChecked: true,
};
