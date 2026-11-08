import type { Area } from '../helpers';

/** The Scenarios page, in Plain and in Technical (the HL7 events on every row, the proof's bases). */
export const area: Area = {
  tag: '@scenarios',
  screens: [
    { path: '/scenarios', heading: 'Scenarios' },
    { path: '/scenarios', heading: 'Scenarios', detail: 'technical' },
    // S8's card follows the chosen mode: Rules only's words and its Run
    { path: '/scenarios?mode=rules', heading: 'Scenarios', name: 'Scenarios in Rules only' },
  ],
  liveScreens: [{ path: '/scenarios', heading: 'Scenarios' }],
  liveWordChecked: true,
};
