import type { TrialRole } from '@/env/mode';

/** The trial's roles, as the mock's users are named, with what each may do (trial-architecture.md 5.8). */
export const TRIAL_ROLES: { role: TrialRole; name: string; can: string }[] = [
  { role: 'approver', name: 'Approver', can: 'Can do everything.' },
  { role: 'operator', name: 'Operator', can: 'Runs scenarios, cannot approve.' },
  {
    role: 'demo',
    name: 'Public demo role',
    can: 'Approves, cannot run or configure; sees the replayed hospital feed.',
  },
  { role: 'judge', name: 'Judge', can: 'Approves, cannot run or configure, as a judge on the public demo.' },
];
