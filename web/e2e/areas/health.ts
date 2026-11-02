import type { Area } from '../helpers';

/**
 * Health: the verdict, the core checks and the five groups, in Plain and in Technical (which opens the groups' data
 * details and the API response). `health.spec.ts` adds a pass with every disclosure open, in all five appearances.
 */
export const area: Area = {
  tag: '@health',
  screens: [
    { path: '/health', heading: 'Health' },
    { path: '/health', heading: 'Health', detail: 'technical' },
  ],
  liveWordChecked: true,
};
