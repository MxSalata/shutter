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
    // Ask about this case, open (beside the case from 1200 px, so at axe's default window too): the example
    // conversation, the suggested questions, the trial's disabled box for a question of one's own and the What-if card
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008' },
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008', detail: 'technical' },
    { path: '/cases/C-000002?ask=1', heading: 'Case C-000002' },
    // Ask beside the case on a wide screen and on a laptop, the case and its board in a narrower column: axe audits the
    // wide state, and the layout run checks both (the case's width beside the panel, and the board's cards in it)
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008', width: 1440 },
    { path: '/cases/C-000008?ask=1', heading: 'Case C-000008', width: 1280, checks: ['layout'] },
  ],
  liveWordChecked: true,
};
