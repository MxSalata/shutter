import { create } from 'zustand';
import { SIGNED_OUT } from '@/api/hooks';
import type { SiteProfile, SiteProfileView, SiteReceiver } from '@/api/types';
import { diffProfiles } from '../profile';
import { QUESTIONS, holdsAnswer, questionOfKey, type QuestionId, type SetupQuestion } from './fields';

/**
 * Set up the site's draft: a copy of the stored profile that lives in this tab's memory and nowhere else. Nothing here
 * is sent anywhere; a reload or a sign-out destroys it, and the only way it is ever stored is the Site profile page's
 * review and its `PUT /site-profile`. Beside the draft the store keeps what the profile itself cannot hold (the
 * validator refuses unknown keys): each receiver's identity on the page (`rids`, which is not its name, so a receiver
 * removed and added again is another receiver), which receivers were added in this draft, who supplied each answer, and
 * which questions were left for now.
 */

/** Who supplied an answer in this draft: the person with the page's control, or Ask Shutter from the person's words. */
export type Provenance = { by: 'you' } | { by: 'ask'; turnId: string; quote: string };

/** How a question stands for one receiver, as its badge says it. */
export type AnswerStatus = 'in_force' | 'you' | 'ask' | 'onboarding' | 'unanswered' | 'left';

/** A draft handed to the Site profile page for its review: the draft as it was, and the version it was made against. */
export interface Handover {
  draft: SiteProfile;
  baseVersion: number;
}

export interface SetupData {
  /** The stored profile the draft started from, or null before the page has read one. */
  base: SiteProfileView | null;
  draft: SiteProfile | null;
  /** One id per entry of `draft.receivers`, in the same order. */
  rids: string[];
  /** The receivers added in this draft, by id: not in the profile in force. */
  added: Record<string, true>;
  /** Where a receiver that is in force stands in `base.profile.receivers`, by id. */
  baseIndex: Record<string, number>;
  /** Counts every change to the draft. */
  revision: number;
  /** Who supplied an answer, by `rid/key`. */
  prov: Record<string, Provenance>;
  /** Questions left for now, by `rid/question`. */
  left: Record<string, true>;
  /** The receiver the workspace is on, or null on the start list. */
  focus: string | null;
  /** The stored version moved while this draft had changes. */
  moved: boolean;
  handover: Handover | null;
}

interface SetupActions {
  /** Takes the stored profile as the page read it: a new draft, or the same one when its version has not moved. */
  open: (view: SiteProfileView) => void;
  /** A person's answer with the page's control: `undefined` removes the key. */
  setKey: (rid: string, key: string, value: unknown) => void;
  leave: (rid: string, question: QuestionId) => void;
  /** Starts a receiver in onboarding's draft shape: no name, no kind, no tier, every feature declared false, no API. */
  addReceiver: () => string;
  /** Takes a receiver added in this draft out of it again. */
  removeAdded: (rid: string) => void;
  focusOn: (rid: string | null) => void;
  /** The draft is the stored profile again, and nothing of the conversation is kept. */
  discard: () => void;
  /** A version was saved: it is the profile in force, and the draft starts from it. */
  saved: (view: SiteProfileView) => void;
  handOver: () => void;
  takeHandover: () => Handover | null;
  /** The Site profile page hands a draft back: receivers keep their ids by name, and a changed answer is the person's. */
  adopt: (draft: SiteProfile) => void;
}

export type SetupState = SetupData & SetupActions;

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

let nextRid = 1;
const newRid = () => `r${nextRid++}`;

const EMPTY: SetupData = {
  base: null,
  draft: null,
  rids: [],
  added: {},
  baseIndex: {},
  revision: 0,
  prov: {},
  left: {},
  focus: null,
  moved: false,
  handover: null,
};

function seeded(view: SiteProfileView, revision: number): SetupData {
  const rids = view.profile.receivers.map(newRid);
  return {
    ...EMPTY,
    base: view,
    draft: clone(view.profile),
    rids,
    baseIndex: Object.fromEntries(rids.map((rid, i) => [rid, i])),
    revision: revision + 1,
  };
}

/** A receiver as Set up the site starts one: the gate blocks every write to it until a person declares what it takes. */
export function blankReceiver(): SiteReceiver {
  return {
    name: '',
    features: { conditional_writes: false, receipts: false, history: false, dry_run: false },
  } as unknown as SiteReceiver;
}

export const useSetup = create<SetupState>((set, get) => ({
  ...EMPTY,
  open: (view) => {
    const s = get();
    if (s.draft && s.base && s.base.version === view.version) return;
    if (s.draft && s.base && isDirty(s)) return set({ moved: true });
    set(seeded(view, s.revision));
  },
  setKey: (rid, key, value) =>
    set((s) => {
      const i = s.rids.indexOf(rid);
      if (!s.draft || i < 0) return s;
      const draft = clone(s.draft);
      const r = draft.receivers[i] as Record<string, unknown>;
      if (value === undefined) delete r[key];
      else r[key] = value;
      const prov = { ...s.prov };
      const was = baseReceiver(s, rid);
      // Back at the value in force, the answer is the one in force again
      if (was && same((was as Record<string, unknown>)[key], value)) delete prov[`${rid}/${key}`];
      else prov[`${rid}/${key}`] = { by: 'you' };
      const left = { ...s.left };
      const q = questionOfKey(key);
      if (q) delete left[`${rid}/${q.id}`];
      return { draft, prov, left, revision: s.revision + 1 };
    }),
  leave: (rid, question) => set((s) => ({ left: { ...s.left, [`${rid}/${question}`]: true } })),
  addReceiver: () => {
    const rid = newRid();
    set((s) => {
      if (!s.draft) return s;
      const draft = clone(s.draft);
      draft.receivers.push(blankReceiver());
      return {
        draft,
        rids: [...s.rids, rid],
        added: { ...s.added, [rid]: true },
        focus: rid,
        revision: s.revision + 1,
      };
    });
    return rid;
  },
  removeAdded: (rid) =>
    set((s) => {
      const i = s.rids.indexOf(rid);
      if (!s.draft || i < 0 || !s.added[rid]) return s;
      const draft = clone(s.draft);
      draft.receivers.splice(i, 1);
      const { [rid]: _gone, ...added } = s.added;
      return {
        draft,
        rids: s.rids.filter((x) => x !== rid),
        added,
        prov: without(s.prov, rid),
        left: without(s.left, rid),
        focus: s.focus === rid ? null : s.focus,
        revision: s.revision + 1,
      };
    }),
  focusOn: (rid) => set({ focus: rid }),
  discard: () => set((s) => (s.base ? seeded(s.base, s.revision) : s)),
  saved: (view) => set((s) => seeded(view, s.revision)),
  handOver: () =>
    set((s) =>
      s.draft && s.base ? { handover: { draft: clone(s.draft), baseVersion: s.base.version } } : s,
    ),
  takeHandover: () => {
    const h = get().handover;
    if (h) set({ handover: null });
    return h;
  },
  adopt: (next) =>
    set((s) => {
      if (!s.draft || !s.base) return s;
      const byName = new Map(s.draft.receivers.map((r, i) => [r.name, s.rids[i]]));
      const taken = new Set<string>();
      const added: Record<string, true> = {};
      const rids = next.receivers.map((r) => {
        const known = byName.get(r.name);
        if (known && !taken.has(known)) {
          taken.add(known);
          if (s.added[known]) added[known] = true;
          return known;
        }
        const rid = newRid();
        added[rid] = true;
        return rid;
      });
      const prov: Record<string, Provenance> = {};
      for (const [at, p] of Object.entries(s.prov)) {
        const [rid, key] = at.split('/');
        const now = rids.indexOf(rid);
        const before = s.rids.indexOf(rid);
        if (now < 0) continue;
        const kept = same(
          (next.receivers[now] as Record<string, unknown>)[key],
          (s.draft.receivers[before] as Record<string, unknown>)[key],
        );
        // An answer changed on the Site profile page is the person's own, whoever drafted it first
        prov[at] = kept ? p : { by: 'you' };
      }
      const baseIndex = Object.fromEntries(Object.entries(s.baseIndex).filter(([rid]) => rids.includes(rid)));
      const keep = (o: Record<string, true>) =>
        Object.fromEntries(Object.entries(o).filter(([at]) => rids.includes(at.split('/')[0])));
      return {
        draft: clone(next),
        rids,
        added,
        baseIndex,
        prov,
        left: keep(s.left) as Record<string, true>,
        focus: s.focus && rids.includes(s.focus) ? s.focus : null,
        revision: s.revision + 1,
      };
    }),
}));

function without<T>(o: Record<string, T>, rid: string): Record<string, T> {
  return Object.fromEntries(Object.entries(o).filter(([at]) => !at.startsWith(`${rid}/`)));
}

/** The receiver's entry in the draft, or undefined when the id is not in it. */
export function receiverOf(s: SetupData, rid: string | null): SiteReceiver | undefined {
  const i = rid ? s.rids.indexOf(rid) : -1;
  return i < 0 ? undefined : s.draft?.receivers[i];
}

/** The receiver's entry in the profile in force, or undefined for one added in this draft. */
export function baseReceiver(s: SetupData, rid: string): SiteReceiver | undefined {
  const i = s.baseIndex[rid];
  return i === undefined || s.added[rid] ? undefined : s.base?.profile.receivers[i];
}

/** Whether the receiver is in the profile in force: only a person changes its kind and its tier. */
export const inForce = (s: SetupData, rid: string): boolean => !s.added[rid] && rid in s.baseIndex;

/** Whether the draft differs from the stored profile. */
export function isDirty(s: SetupData): boolean {
  return !!s.draft && !!s.base && !same(s.draft, s.base.profile);
}

/** The draft's changes in words, as the review lists them. */
export function changesOf(s: SetupData) {
  return s.draft && s.base ? diffProfiles(s.base.profile, s.draft) : [];
}

/** How a question stands for a receiver. */
export function statusOf(s: SetupData, rid: string, q: SetupQuestion): AnswerStatus {
  const r = receiverOf(s, rid);
  if (!r) return 'unanswered';
  const drafted = q.keys.some((k) => s.prov[`${rid}/${k}`]?.by === 'ask');
  const was = baseReceiver(s, rid);
  if (was) {
    const changed = q.keys.some(
      (k) => !same((was as Record<string, unknown>)[k], (r as Record<string, unknown>)[k]),
    );
    if (changed) return drafted ? 'ask' : 'you';
    return was.draft === true ? 'onboarding' : 'in_force';
  }
  if (holdsAnswer(q, r)) return drafted ? 'ask' : 'you';
  return s.left[`${rid}/${q.id}`] ? 'left' : 'unanswered';
}

/** The next question to ask about a receiver: the first that is neither answered nor left, or null. */
export function nextQuestion(s: SetupData, rid: string): SetupQuestion | null {
  return QUESTIONS.find((q) => statusOf(s, rid, q) === 'unanswered') ?? null;
}

/** How many of the checklist's questions hold an answer for a receiver. */
export function progress(s: SetupData, rid: string): { answered: number; total: number } {
  const answered = QUESTIONS.filter((q) => !['unanswered', 'left'].includes(statusOf(s, rid, q))).length;
  return { answered, total: QUESTIONS.length };
}

/** The questions of a receiver that hold no answer, in order. */
export function unansweredOf(s: SetupData, rid: string): SetupQuestion[] {
  return QUESTIONS.filter((q) => ['unanswered', 'left'].includes(statusOf(s, rid, q)));
}

/** What stops the review before `checkDraft` runs: a receiver being added with no name, kind or tier. */
export interface ReviewStop {
  rid: string;
  question: QuestionId;
  message: string;
}

export function reviewStop(s: SetupData): ReviewStop | null {
  for (const rid of s.rids) {
    if (!s.added[rid]) continue;
    const r = receiverOf(s, rid)!;
    for (const q of QUESTIONS) {
      if (!q.required || holdsAnswer(q, r)) continue;
      const of = r.name.trim() || 'the receiver being added';
      return {
        rid,
        question: q.id,
        message:
          q.id === 'name'
            ? 'Name the receiver being added before review'
            : `Answer the ${q.id === 'category' ? 'kind' : 'tier'} of ${of} before review`,
      };
    }
  }
  return null;
}

// A sign-out forgets the draft: signing in as someone else is not a hand-over
if (typeof window !== 'undefined')
  window.addEventListener(SIGNED_OUT, () =>
    useSetup.setState({ ...EMPTY, revision: useSetup.getState().revision + 1 }),
  );

/** For tests: no draft, no hand-over. */
export function resetSetupForTests(): void {
  nextRid = 1;
  useSetup.setState({ ...EMPTY });
}
