import type { Area } from '../helpers';

/** The Incidents list and an incident. */
export const area: Area = {
  tag: '@incidents',
  screens: [
    { path: '/incidents', heading: 'Incidents' },
    { path: '/incidents/I-000001', heading: 'Incident I-000001' },
  ],
  liveWordChecked: false,
};
