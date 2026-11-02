import { CHAPTERS, SCOPES, stepAt, type GuideChapter, type GuideScope, type GuideStep } from './registry';

/**
 * The guide's progress as it is kept on this device: the route, the step in hand (its path, `s2/decision`), the
 * chapters finished and whether the welcome may open by itself. It holds nothing about cases, patients or approvals.
 */
export interface GuideProgress {
  version: 2;
  scope: GuideScope;
  /** The step in hand, or null before the guide starts and after it ends. */
  at: string | null;
  completed: string[];
  /** The welcome does not open by itself: Don't show again, or the tour was finished. */
  dismissed: boolean;
}

export const INITIAL: GuideProgress = {
  version: 2,
  scope: 'quick',
  at: null,
  completed: [],
  dismissed: false,
};

export interface GuidePosition {
  chapter: GuideChapter;
  step: GuideStep;
  path: string;
  /** 1-based, within the route ("Step 3 of 9" counts the route, not the chapter). */
  n: number;
  m: number;
  first: boolean;
  last: boolean;
}

/** The step the progress points at, or undefined when the guide is not under way. */
export function positionOf(p: GuideProgress): GuidePosition | undefined {
  const order = SCOPES[p.scope];
  const i = p.at ? order.indexOf(p.at) : -1;
  const found = stepAt(p.at);
  if (i < 0 || !found) return undefined;
  return { ...found, path: p.at!, n: i + 1, m: order.length, first: i === 0, last: i === order.length - 1 };
}

/** Whether the welcome opens by itself: never started, never dismissed. */
export function welcomeDue(p: GuideProgress): boolean {
  return !p.dismissed && p.at === null && p.completed.length === 0;
}

const chapterOf = (path: string) => path.split('/')[0];
const withCompleted = (completed: string[], id: string) =>
  completed.includes(id) ? completed : [...completed, id];

/** The route from its first step. */
export function start(p: GuideProgress, scope: GuideScope): GuideProgress {
  return { ...p, scope, at: SCOPES[scope][0] };
}

/** The end of the tour: the chapters finished so far are kept, and the welcome no longer opens by itself. */
function finish(p: GuideProgress, completed: string[]): GuideProgress {
  return { ...p, at: null, completed, dismissed: true };
}

/** The next step; leaving a chapter's last step on the route finishes the chapter; the last step ends the tour. */
export function next(p: GuideProgress): GuideProgress {
  const pos = positionOf(p);
  if (!pos) return p;
  const following = SCOPES[p.scope][pos.n];
  const leaving = !following || chapterOf(following) !== pos.chapter.id;
  const completed = leaving ? withCompleted(p.completed, pos.chapter.id) : p.completed;
  if (!following) return finish(p, completed);
  return { ...p, at: following, completed };
}

/** The step before, across chapters; nothing before the first. */
export function back(p: GuideProgress): GuideProgress {
  const pos = positionOf(p);
  if (!pos || pos.first) return p;
  return { ...p, at: SCOPES[p.scope][pos.n - 2] };
}

/** The first step of the next chapter on the route, leaving this one unfinished; past the last, the end. */
export function skipChapter(p: GuideProgress): GuideProgress {
  const pos = positionOf(p);
  if (!pos) return p;
  const after = SCOPES[p.scope].slice(pos.n).find((path) => chapterOf(path) !== pos.chapter.id);
  return after ? { ...p, at: after } : finish(p, p.completed);
}

/** A chapter picked from the list: on the current route when it has the chapter, otherwise on every screen's. */
export function goToChapter(p: GuideProgress, id: string): GuideProgress {
  const firstOn = (scope: GuideScope) => SCOPES[scope].find((path) => chapterOf(path) === id);
  const here = firstOn(p.scope);
  if (here) return { ...p, at: here };
  const all = firstOn('all');
  return all ? { ...p, scope: 'all', at: all } : p;
}

/** How many steps a chapter has on a route (on every screen's when the route does not pass it). */
export function stepsIn(chapterId: string, scope: GuideScope): number {
  const n = SCOPES[scope].filter((path) => chapterOf(path) === chapterId).length;
  return n || SCOPES.all.filter((path) => chapterOf(path) === chapterId).length;
}

/** Whether a chapter is on a route. */
export const onRoute = (chapterId: string, scope: GuideScope) =>
  SCOPES[scope].some((path) => chapterOf(path) === chapterId);

/** Whether a stored value is progress this version of the guide can use; anything else starts afresh. */
export function isProgress(v: unknown): v is GuideProgress {
  if (!v || typeof v !== 'object') return false;
  const p = v as Record<string, unknown>;
  return (
    p.version === 2 &&
    (p.scope === 'quick' || p.scope === 'all' || p.scope === 'engineer') &&
    (p.at === null || (typeof p.at === 'string' && SCOPES[p.scope].includes(p.at))) &&
    Array.isArray(p.completed) &&
    p.completed.every((c) => typeof c === 'string' && CHAPTERS.some((x) => x.id === c)) &&
    typeof p.dismissed === 'boolean'
  );
}
