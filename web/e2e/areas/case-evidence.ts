import type { Area } from '../helpers';

/** A case's Evidence and Audit trail tabs, and Ask about this case, in Plain and in Technical. */
export const area: Area = {
  tag: '@case-evidence',
  screens: [
    { path: '/cases/C-000008?tab=evidence', heading: 'Case C-000008' },
    { path: '/cases/C-000008?tab=evidence', heading: 'Case C-000008', detail: 'technical' },
    // S23a's bed conflict and pending messages, and S4's free text in the message, with every data detail open
    { path: '/cases/C-000058?tab=evidence', heading: 'Case C-000058', detail: 'technical' },
    { path: '/cases/C-000004?tab=evidence', heading: 'Case C-000004', detail: 'technical', checks: ['a11y'] },
    // The audit trail: one round with the plan's rationale folded, and two rounds
    { path: '/cases/C-000008?tab=audit', heading: 'Case C-000008' },
    { path: '/cases/C-000007?tab=audit', heading: 'Case C-000007' },
    { path: '/cases/C-000007?tab=audit', heading: 'Case C-000007', detail: 'technical' },
    // Ask about this case, open (a drawer below 1440 px): the example conversation, the suggested questions, the
    // trial's disabled box for a question of one's own and the What-if card
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008' },
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008', detail: 'technical' },
    { path: '/cases/C-000002?ask=1', heading: 'Case C-000002' },
  ],
  liveWordChecked: true,
};
