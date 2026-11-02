import type { Area } from '../helpers';

/**
 * The Evaluation: the page in Plain and in Technical (where every data disclosure is open, the document's JSON
 * included), and the table opened filtered by the address, as the engineers' tour opens it. Every disclosure and table
 * view open, in both levels, is evaluation.spec.ts's.
 */
export const area: Area = {
  tag: '@evaluation',
  screens: [
    { path: '/evaluation', heading: 'Evaluation' },
    { path: '/evaluation', heading: 'Evaluation', detail: 'technical' },
    { path: '/evaluation?show=rules-differs', heading: 'Evaluation' },
  ],
  liveWordChecked: true,
};
