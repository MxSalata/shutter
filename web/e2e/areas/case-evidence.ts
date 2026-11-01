import type { Area } from '../helpers';

/** A case's Evidence and Audit trail tabs, and Ask about this case. */
export const area: Area = {
  tag: '@case-evidence',
  screens: [
    { path: '/cases/C-000008?tab=evidence', heading: 'Case C-000008' },
    { path: '/cases/C-000007?tab=audit', heading: 'Case C-000007' },
    // Ask about this case, open: the example conversation, the suggested questions and the What-if card
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008' },
    { path: '/cases/C-000002?ask=1', heading: 'Case C-000002' },
  ],
  liveWordChecked: false,
};
