import { chapterById, SCOPES, type GuideChapter, type GuideScope, type GuideStep } from './registry';

/**
 * The guide's progress as it is kept on this device: where the reader is, the chapters finished and whether the
 * welcome may open by itself. It holds nothing about cases, patients or approvals.
 */
export interface GuideProgress {
  version: 1;
  scope: GuideScope;
  /** The chapter in hand, or null before the guide starts and after it ends. */
  chapter: string | null;
  step: number;
  completed: string[];
  /** The welcome does not open by itself: Don't show again, or the guide was finished. */
  dismissed: boolean;
}

export const INITIAL: GuideProgress = {
  version: 1,
  scope: 'quick',
  chapter: null,
  step: 0,
  completed: [],
  dismissed: false,
};

export interface GuidePosition {
  chapter: GuideChapter;
  step: GuideStep;
  /** 1-based, within the chapter. */
  n: number;
  m: number;
  /** 1-based, within the scope. */
  chapterN: number;
  chapterM: number;
  first: boolean;
  last: boolean;
}

/** The step the progress points at, or undefined when the guide is not under way. */
export function positionOf(p: GuideProgress): GuidePosition | undefined {
  const order = SCOPES[p.scope];
  const i = p.chapter ? order.indexOf(p.chapter) : -1;
  const chapter = chapterById(p.chapter);
  if (i < 0 || !chapter) return undefined;
  const s = Math.min(Math.max(p.step, 0), chapter.steps.length - 1);
  return {
    chapter,
    step: chapter.steps[s],
    n: s + 1,
    m: chapter.steps.length,
    chapterN: i + 1,
    chapterM: order.length,
    first: i === 0 && s === 0,
    last: i === order.length - 1 && s === chapter.steps.length - 1,
  };
}

/** Whether the welcome opens by itself: never started, never dismissed. */
export function welcomeDue(p: GuideProgress): boolean {
  return !p.dismissed && p.chapter === null && p.completed.length === 0;
}

const withCompleted = (completed: string[], id: string) =>
  completed.includes(id) ? completed : [...completed, id];

/** The scope from its first chapter. */
export function start(p: GuideProgress, scope: GuideScope): GuideProgress {
  return { ...p, scope, chapter: SCOPES[scope][0], step: 0 };
}

/** The end of the guide: the chapters finished so far are kept, and the welcome no longer opens by itself. */
function finish(p: GuideProgress, completed: string[]): GuideProgress {
  return { ...p, chapter: null, step: 0, completed, dismissed: true };
}

/** The chapter after the current one, from its first step, or the end. */
function nextChapter(p: GuideProgress, completed: string[]): GuideProgress {
  const order = SCOPES[p.scope];
  const i = p.chapter ? order.indexOf(p.chapter) : -1;
  if (i < 0 || i === order.length - 1) return finish(p, completed);
  return { ...p, chapter: order[i + 1], step: 0, completed };
}

/** The next step; the last step of a chapter finishes it. */
export function next(p: GuideProgress): GuideProgress {
  const pos = positionOf(p);
  if (!pos) return p;
  if (pos.n < pos.m) return { ...p, step: pos.n };
  return nextChapter(p, withCompleted(p.completed, pos.chapter.id));
}

/** The step before, across chapters; nothing before the first. */
export function back(p: GuideProgress): GuideProgress {
  const pos = positionOf(p);
  if (!pos || pos.first) return p;
  if (pos.n > 1) return { ...p, step: pos.n - 2 };
  const order = SCOPES[p.scope];
  const previous = chapterById(order[pos.chapterN - 2])!;
  return { ...p, chapter: previous.id, step: previous.steps.length - 1 };
}

/** The next chapter, leaving this one unfinished. */
export function skipChapter(p: GuideProgress): GuideProgress {
  return positionOf(p) ? nextChapter(p, p.completed) : p;
}

/** A chapter picked from Help: in the current scope when it has the chapter, otherwise among all sections. */
export function goToChapter(p: GuideProgress, id: string): GuideProgress {
  if (!chapterById(id)) return p;
  const scope = SCOPES[p.scope].includes(id) ? p.scope : 'all';
  return { ...p, scope, chapter: id, step: 0 };
}

/** Whether a stored value is progress this version of the guide can use; anything else starts afresh. */
export function isProgress(v: unknown): v is GuideProgress {
  if (!v || typeof v !== 'object') return false;
  const p = v as Record<string, unknown>;
  return (
    p.version === 1 &&
    (p.scope === 'quick' || p.scope === 'all') &&
    (p.chapter === null || (typeof p.chapter === 'string' && SCOPES[p.scope].includes(p.chapter))) &&
    typeof p.step === 'number' &&
    Number.isInteger(p.step) &&
    p.step >= 0 &&
    Array.isArray(p.completed) &&
    p.completed.every((c) => typeof c === 'string') &&
    typeof p.dismissed === 'boolean'
  );
}
