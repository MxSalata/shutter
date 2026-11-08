import { create } from 'zustand';
import { SIGNED_OUT } from '@/api/hooks';
import { useAppearance } from '@/stores/appearance';
import { compactBanner } from '@/trial/visit';
import * as guide from './controller';
import type { GuideProgress } from './controller';
import type { GuideScope } from './registry';
import { forgetProgress, loadProgress, saveProgress, snoozeWelcome, welcomeSnoozed } from './storage';

/**
 * What the guide shows now: nothing, the welcome, a step's card before its section, the chapter picker, or the finish
 * card. Only the progress is stored; the phase is this visit's.
 */
export type GuidePhase = 'closed' | 'welcome' | 'step' | 'chapters' | 'finished';

interface GuideState {
  progress: GuideProgress;
  phase: GuidePhase;
  /**
   * Explore on my own, or the welcome closed: it stays closed for the rest of the visit and opens again on the next.
   * The visit outlasts a reload and a link into the trial (storage.ts, snoozeWelcome).
   */
  snoozed: boolean;
  /** The step after Next approved the held case for the reader: its card says so, once. */
  approvedForYou: string | null;
  /** A control the guide points at with no card (the finish card's "Run S20 yourself"). */
  pointAt: string | null;
  /** Changes on every step opened, so opening the same step again plays its movements again. */
  openedAt: number;
  openWelcome(): void;
  notNow(): void;
  dontShowAgain(): void;
  begin(scope: GuideScope): void;
  /** Next; `approved` says the guide approved the held case for the reader on the way. */
  next(approved?: boolean): void;
  back(): void;
  skipChapter(): void;
  /** Escape, Exit guide or the card's close: closes the guide where it is, finishing nothing. */
  exit(): void;
  resume(): void;
  openChapters(): void;
  chooseChapter(id: string): void;
  point(action: string | null): void;
  /** Sign-out: the guide closes and its state in memory is read afresh from the device. */
  reset(): void;
}

export const useGuide = create<GuideState>()((set, get) => {
  const save = (progress: GuideProgress, more: Partial<GuideState> = {}) => {
    saveProgress(progress);
    // A step moved past the last one ends the tour, on the finish card
    set({
      progress,
      phase: progress.at ? 'step' : 'finished',
      openedAt: Date.now(),
      approvedForYou: null,
      pointAt: null,
      ...more,
    });
  };
  return {
    progress: loadProgress(),
    phase: 'closed',
    snoozed: welcomeSnoozed(),
    approvedForYou: null,
    pointAt: null,
    openedAt: 0,
    openWelcome: () => set({ phase: 'welcome', pointAt: null }),
    notNow: () => {
      snoozeWelcome();
      set({ phase: 'closed', snoozed: true });
    },
    dontShowAgain: () => {
      const progress = { ...get().progress, dismissed: true };
      saveProgress(progress);
      set({ progress, phase: 'closed' });
    },
    begin: (scope) => {
      // The engineers' tour reads with Technical on: the receipt's keys, the gate's codes, what each agent cited
      if (scope === 'engineer') useAppearance.getState().setDetail('technical');
      save(guide.start(get().progress, scope));
    },
    next: (approved) => {
      const progress = guide.next(get().progress);
      save(progress, approved && progress.at ? { approvedForYou: progress.at } : {});
    },
    back: () => save(guide.back(get().progress)),
    skipChapter: () => save(guide.skipChapter(get().progress)),
    exit: () => {
      // The welcome closed by Escape or its close button is put off for the visit, as Explore on my own puts it off
      if (get().phase === 'welcome') {
        snoozeWelcome();
        set({ phase: 'closed', approvedForYou: null, snoozed: true });
      } else set({ phase: 'closed', approvedForYou: null });
    },
    resume: () => {
      const { progress } = get();
      if (guide.positionOf(progress)) set({ phase: 'step', openedAt: Date.now(), pointAt: null });
      else set({ phase: 'welcome', pointAt: null });
    },
    openChapters: () => set({ phase: 'chapters', pointAt: null }),
    chooseChapter: (id) => save(guide.goToChapter(get().progress, id)),
    point: (action) => set({ phase: 'closed', pointAt: action }),
    reset: () => {
      forgetProgress();
      set({
        progress: loadProgress(),
        phase: 'closed',
        snoozed: welcomeSnoozed(),
        approvedForYou: null,
        pointAt: null,
      });
    },
  };
});

// A sign-out anywhere in the page closes the guide and drops its copy in memory (useSignOut sends the event)
if (typeof window !== 'undefined') window.addEventListener(SIGNED_OUT, () => useGuide.getState().reset());

// The banner keeps to one line once the welcome has closed, for the rest of the tab's visit to the trial
useGuide.subscribe((now, before) => {
  if (before.phase === 'welcome' && now.phase !== 'welcome') compactBanner();
});
