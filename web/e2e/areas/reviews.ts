import type { Area } from '../helpers';

/**
 * The production review: the list and a review, in Plain and in Technical, a review the agent ranked, and a review with
 * one finding open.
 */
export const area: Area = {
  tag: '@reviews',
  screens: [
    { path: '/reviews', heading: 'Production review' },
    { path: '/reviews/PR-000001', heading: 'Review PR-000001' },
    { path: '/reviews/PR-000003', heading: 'Review PR-000003' },
    // The newest review of Shutter's own production, ranked: the agent's card above the findings
    {
      path: '/reviews/PR-000004',
      heading: 'Review PR-000004',
      name: 'Review PR-000004, ranked by the agent',
    },
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
