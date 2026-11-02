/**
 * Everything a trial page adds to the shell, in one chunk that only trial pages load (main.tsx): the banner and the
 * pill, the user menu's trial items, Leave trial and its confirm, Help's trial menu and the guide, which runs only in
 * the trial.
 */
export { TrialBanner } from './TrialBanner';
export { TrialPill } from './TrialPill';
export { TrialRoleItems } from './TrialRoleItems';
export { LeaveTrialConfirm, LeaveTrialItem } from './LeaveTrial';
export { Guide } from '@/features/guide/Guide';
export { TrialHelpMenu } from '@/features/guide/HelpMenu';
