import { create } from 'zustand';
import * as guide from './controller';
import type { GuideProgress } from './controller';
import type { GuideScope } from './registry';
import { forgetProgress, loadProgress, saveProgress } from './storage';

/**
 * What the guide shows now: nothing, the welcome, a step's dialog, a step's section on the page (with Continue guide
 * beside it), or the chapter picker. Only the progress is stored; the phase is this visit's.
 */
export type GuidePhase = 'closed' | 'welcome' | 'step' | 'shown' | 'chapters';

interface GuideState {
  progress: GuideProgress;
  phase: GuidePhase;
  /** Not now: the welcome stays closed for the rest of the visit and opens again on the next. */
  snoozed: boolean;
  /** Changes on every Show this section, so showing the same section again runs again. */
  shownAt: number;
  openWelcome(): void;
  notNow(): void;
  dontShowAgain(): void;
  begin(scope: GuideScope): void;
  next(): void;
  back(): void;
  skipChapter(): void;
  /** Escape, Exit guide or a click outside: closes the guide where it is, finishing nothing. */
  exit(): void;
  resume(): void;
  openChapters(): void;
  chooseChapter(id: string): void;
  show(): void;
  continueGuide(): void;
  /** Sign-out: the guide closes and its state in memory is read afresh from the device. */
  reset(): void;
}

export const useGuide = create<GuideState>()((set, get) => {
  const save = (progress: GuideProgress, phase: GuidePhase) => {
    saveProgress(progress);
    // A step moved past the last one ends the guide
    set({ progress, phase: phase === 'step' && !progress.chapter ? 'closed' : phase });
  };
  return {
    progress: loadProgress(),
    phase: 'closed',
    snoozed: false,
    shownAt: 0,
    openWelcome: () => set({ phase: 'welcome' }),
    notNow: () => set({ phase: 'closed', snoozed: true }),
    dontShowAgain: () => save({ ...get().progress, dismissed: true }, 'closed'),
    begin: (scope) => save(guide.start(get().progress, scope), 'step'),
    next: () => save(guide.next(get().progress), 'step'),
    back: () => save(guide.back(get().progress), 'step'),
    skipChapter: () => save(guide.skipChapter(get().progress), 'step'),
    exit: () => set({ phase: 'closed' }),
    resume: () => {
      const { progress } = get();
      if (guide.positionOf(progress)) set({ phase: 'step' });
      else set({ phase: 'welcome' });
    },
    openChapters: () => set({ phase: 'chapters' }),
    chooseChapter: (id) => save(guide.goToChapter(get().progress, id), 'step'),
    show: () => set({ phase: 'shown', shownAt: Date.now() }),
    continueGuide: () => set({ phase: 'step' }),
    reset: () => {
      forgetProgress();
      set({ progress: loadProgress(), phase: 'closed', snoozed: false, shownAt: 0 });
    },
  };
});
