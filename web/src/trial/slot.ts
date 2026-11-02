import type * as Chrome from './chrome';

/**
 * The trial's chrome (the banner, the pill, its menus, Leave trial and the guide), loaded at start by trial pages only
 * (main.tsx), in its own chunk, so a live page downloads none of it. The shell reads it here: null in a live page.
 */
export type TrialChrome = typeof Chrome;

let chrome: TrialChrome | null = null;

export function provideTrialChrome(c: TrialChrome | null): void {
  chrome = c;
}

export const trialChrome = (): TrialChrome | null => chrome;
