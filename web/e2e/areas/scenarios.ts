import type { Area } from '../helpers';

/** The Scenarios page, in Plain and in Technical (the HL7 events on every row, the proof's bases). */
export const area: Area = {
  tag: '@scenarios',
  screens: [
    { path: '/scenarios', heading: 'Scenarios' },
    { path: '/scenarios', heading: 'Scenarios', detail: 'technical' },
  ],
  liveScreens: [{ path: '/scenarios', heading: 'Scenarios' }],
  liveWordChecked: true,
};
