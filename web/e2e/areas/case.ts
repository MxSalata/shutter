import type { Area } from '../helpers';

/** A case's page: its header, the Summary tab's story, the board, the receipt and the approval. */
export const area: Area = {
  tag: '@case',
  screens: [
    { path: '/cases/C-000009', heading: 'Case C-000009' },
    { path: '/cases/C-000002', heading: 'Case C-000002' },
    { path: '/cases/C-000007', heading: 'Case C-000007' },
    { path: '/cases/C-000008', heading: 'Case C-000008', checks: ['a11y'] },
    // The S8 comparison opened as the guide links to it
    { path: '/cases/C-000008?show=compare', heading: 'Case C-000008' },
    // Every story step open, on a case that waits for a person, one escalated by the board, a resolved one and two
    // blocked ones with the gate's checks and the next action
    { path: '/cases/C-000002', heading: 'Case C-000002', steps: 'open' },
    { path: '/cases/C-000008', heading: 'Case C-000008', steps: 'open' },
    { path: '/cases/C-000009', heading: 'Case C-000009', steps: 'open' },
    { path: '/cases/C-000053', heading: 'Case C-000053', steps: 'open' },
    { path: '/cases/C-000020', heading: 'Case C-000020', steps: 'open' },
    // S22's case at the patient records system: its category beside the outcome and the steps that correct its history
    { path: '/cases/C-000055', heading: 'Case C-000055', checks: ['a11y'] },
    // S23a's case that waited for the bed's occupant to leave, and S25's message with the site's own segment, every
    // step open
    { path: '/cases/C-000058', heading: 'Case C-000058', steps: 'open', checks: ['a11y'] },
    { path: '/cases/C-000064', heading: 'Case C-000064', steps: 'open', checks: ['a11y'] },
  ],
  liveScreens: [{ path: '/cases/C-000002', heading: 'Case C-000002' }],
  liveWordChecked: false,
};
