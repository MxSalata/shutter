import type { Area } from '../helpers';

/** The Incidents list and an incident, each as the newcomer reads it (Plain) and as the engineer does (Technical). */
export const area: Area = {
  tag: '@incidents',
  screens: [
    { path: '/incidents', heading: 'Incidents' },
    { path: '/incidents/I-000001', heading: 'Incident I-000001' },
    { path: '/incidents', heading: 'Incidents', detail: 'technical' },
    { path: '/incidents/I-000001', heading: 'Incident I-000001', detail: 'technical' },
  ],
  liveWordChecked: true,
};
