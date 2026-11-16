import { create } from 'zustand';
import { SIGNED_OUT } from '@/api/hooks';
import type { SetupTurnAsked, SetupTurnView, SiteProfile, SiteProfileView, SiteReceiver } from '@/api/types';
import { diffProfiles } from '../profile';
import {
  QUESTIONS,
  answerText,
  consequence,
  holdsAnswer,
  questionOfKey,
  type QuestionId,
  type SetupQuestion,
} from './fields';
import { applyBatch, checkTurn, named } from './proposals';

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

/** One answer Ask Shutter drafted, as the review lists it: the page's words for it, never the model's. */
export interface DraftedAnswer {
  /**
   * The receiver: its id on the page (the store's, carried over to the Site profile page with the hand-over, so a rename
   * there keeps the answer), its name in the draft when it was handed over, and the key the value is stored under.
   */
  rid: string;
  receiver: string;
  key: string;
  /** What the answer is: "Kind of system". */
  label: string;
  /** The value in the page's words: "Current state". */
  value: string;
  /** The person's own words it was read from. */
  quote: string;
  /** What the answer does, read from the draft. */
  consequence: string;
}

/** A draft handed to the Site profile page for its review: the draft as it was, and the version it was made against. */
export interface Handover {
  draft: SiteProfile;
  baseVersion: number;
  /** The page's id of each receiver of `draft`, in its order. */
  rids: string[];
  /** The answers in it that Ask Shutter drafted and the person has not changed since. */
  drafted: DraftedAnswer[];
}

/** What a drafted answer replaced, kept for Undo. */
interface Replaced {
  key: string;
  to: unknown;
  from: unknown;
  provenance?: Provenance;
}

/** One exchange with Ask Shutter: what the person typed on a question's card, and what came of it. */
export interface TurnEntry {
  /** The turn's id on the server. */
  id: string;
  rid: string;
  /** The question whose card the text was typed on. */
  question: QuestionId;
  text: string;
  /**
   * reading: sent, not answered yet. used: its answers are in the draft. nothing: read, with nothing to draft. unused:
   * answered, and dropped by the page's own checks. failed: refused by the core, or no answer. cancelled: dropped by
   * the person, a discard or the review.
   */
  state: 'reading' | 'used' | 'nothing' | 'unused' | 'failed' | 'cancelled';
  /** Ask Shutter's own sentences. */
  say?: string;
  /** What entered the draft from this turn. */
  drafted?: Replaced[];
  /** Why nothing was used. */
  note?: string;
  undone?: boolean;
  /** Who read it: the run's model (`mock` under the API mimic) and its message in the production, for the trace. */
  model?: string | null;
  run?: string | null;
  /** The run's message in the Management Portal, as the server gives it (under its namespace's own portal path). */
  link?: string | null;
}

/** The turn being read: one at a time. */
export interface PendingTurn {
  turnId: string;
  rid: string;
  question: QuestionId;
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
  /**
   * Which draft this is: a new one each time the draft starts afresh (a discard, a save, a new stored version, a
   * sign-out), so an answer to a send made before then is not taken into it.
   */
  epoch: number;
  handover: Handover | null;
  /** The conversation with Ask Shutter, as the server names it; null before the first turn and after a discard. */
  conversation: string | null;
  turns: TurnEntry[];
  pending: PendingTurn | null;
  /** How often a typed answer drafted nothing for a question, by `rid/question`: after two, the control answers. */
  misses: Record<string, number>;
  /** The question Ask Shutter's last turn suggested next, when it is an unanswered one of the checklist. */
  suggested: { rid: string; question: QuestionId } | null;
  /**
   * What is typed in a card's box and not sent yet, by `rid/question`: kept here so it outlives the page's two layouts
   * (a window that crosses the wide breakpoint draws the panes afresh). It is sent nowhere until the person sends it.
   */
  typed: Record<string, string>;
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
  /**
   * The Site profile page hands a draft back: receivers keep their ids by the page's ids where it gives one for each
   * (so a rename there keeps a receiver and its drafted answers), else by name; a changed answer is the person's.
   */
  adopt: (draft: SiteProfile, rids?: string[]) => void;
  /** A typed answer was sent: the server opened its turn. */
  /** `epoch` is the draft's when the send was made: an answer that arrives for another draft is ignored. */
  sent: (rid: string, question: QuestionId, text: string, asked: SetupTurnAsked, epoch?: number) => void;
  /** The turn being read is dropped: whatever comes back for it is not used. */
  cancelPending: () => void;
  /**
   * A turn came back. Its answers enter the draft only when it is still the turn being read, the conversation, the
   * receiver and the stored version are the ones it was sent for, each field still holds what the turn replaced, and
   * the page's own copy of the core's checks passes on the draft as it is now. Otherwise the whole batch is dropped.
   */
  /** <var>kindRead</var>: one of the site's own active entries reads a receiver's kind, so no kind is drafted. */
  settle: (view: SetupTurnView, kindRead?: boolean) => void;
  /** Puts back what a turn's drafted answers replaced, where they are still the drafted ones. */
  undo: (turnId: string) => void;
  tookSuggestion: () => void;
  /** What stands in a card's box as the person types. */
  type: (rid: string, question: QuestionId, text: string) => void;
}

export type SetupState = SetupData & SetupActions;

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x)) as T;
const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

let nextRid = 1;
let epochs = 0;
export const newRid = () => `r${nextRid++}`;

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
  epoch: 0,
  handover: null,
  conversation: null,
  turns: [],
  pending: null,
  misses: {},
  suggested: null,
  typed: {},
};

/** What the page says of a turn whose answers could not be used because the draft is no longer the one it was sent for. */
export const CHANGED_MEANWHILE = 'Not used: the draft changed meanwhile.';

function seeded(view: SiteProfileView, revision: number): SetupData {
  const rids = view.profile.receivers.map(newRid);
  return {
    ...EMPTY,
    epoch: ++epochs,
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
      s.draft && s.base
        ? {
            // A turn still being read is dropped: the draft under review cannot change
            ...dropPending(s),
            handover: {
              draft: clone(s.draft),
              baseVersion: s.base.version,
              rids: [...s.rids],
              drafted: draftedAnswers(s),
            },
          }
        : s,
    ),
  takeHandover: () => {
    const h = get().handover;
    if (h) set({ handover: null });
    return h;
  },
  adopt: (next, pageRids) =>
    set((s) => {
      if (!s.draft || !s.base) return s;
      const byName = new Map(s.draft.receivers.map((r, i) => [r.name, s.rids[i]]));
      const taken = new Set<string>();
      const added: Record<string, true> = {};
      // The page's own ids, where it gives one for each receiver: a receiver renamed there is the same receiver
      const byId = pageRids && pageRids.length === next.receivers.length ? pageRids : null;
      const rids = next.receivers.map((r, i) => {
        const id = byId?.[i];
        if (id && s.rids.includes(id) && !taken.has(id)) {
          taken.add(id);
          if (s.added[id]) added[id] = true;
          return id;
        }
        if (byId) {
          const rid = newRid();
          added[rid] = true;
          return rid;
        }
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
  sent: (rid, question, text, asked, epoch) =>
    set((s) =>
      // Sent from a draft discarded, saved or signed out of since: its conversation is not this draft's
      epoch !== undefined && epoch !== s.epoch
        ? s
        : {
            conversation: asked.conversation,
            turns: [...s.turns, { id: asked.turnId, rid, question, text, state: 'reading' }],
            pending: { turnId: asked.turnId, rid, question },
          },
    ),
  cancelPending: () => set((s) => dropPending(s)),
  settle: (view, kindRead = false) =>
    set((s) => {
      const p = s.pending;
      // Not the turn being read (cancelled, discarded, signed out since): nothing of it is used
      if (!p || p.turnId !== view.turnId || !s.draft || !s.base) return s;
      const end = (entry: Partial<TurnEntry>, more: Partial<SetupData> = {}): Partial<SetupData> => ({
        turns: s.turns.map((t) =>
          t.id === view.turnId
            ? { ...t, model: view.model, run: view.ensMessageId, link: view.messageLink ?? null, ...entry }
            : t,
        ),
        pending: null,
        ...more,
      });
      const missed = {
        ...s.misses,
        [`${p.rid}/${p.question}`]: (s.misses[`${p.rid}/${p.question}`] ?? 0) + 1,
      };
      if (view.state !== 'answered' || !view.turn)
        return end({ state: 'failed', note: view.error || 'no answer came back' }, { misses: missed });
      const i = s.rids.indexOf(p.rid);
      const r = i < 0 ? undefined : s.draft.receivers[i];
      // The stored version moved under this draft: what it was checked against is no longer the profile in force
      if (
        s.moved ||
        !r ||
        r.name !== view.receiver ||
        named(s.draft, r.name) > 1 ||
        view.conversation !== s.conversation ||
        view.baseVersion !== s.base.version
      )
        return end({ state: 'unused', note: CHANGED_MEANWHILE });
      const checked = checkTurn(view.turn, s.base.profile, s.draft, r.name, kindRead);
      if (!checked.ok) return end({ state: 'unused', note: `Not used: ${checked.problem}.` });
      const entry = r as Record<string, unknown>;
      const proposals = checked.turn.proposals;
      // Each field still holds what the core saw when the turn was sent
      const moved = (view.turn.proposals ?? []).some((sent) => {
        const now = entry[sent.field.split('.')[1]];
        return !same(now ?? null, sent.from ?? null);
      });
      if (moved) return end({ state: 'unused', note: CHANGED_MEANWHILE });
      const ask = checked.turn.ask ? questionOfKey(checked.turn.ask.field.split('.')[1]) : undefined;
      if (!proposals.length)
        return end(
          { state: 'nothing', say: checked.turn.say },
          { misses: missed, suggested: suggestion(s, p.rid, ask) },
        );
      const draft = applyBatch(s.draft, r.name, proposals);
      const prov = { ...s.prov };
      const left = { ...s.left };
      const drafted: Replaced[] = proposals.map((x) => {
        const key = x.field.split('.')[1];
        const at = `${p.rid}/${key}`;
        const replaced: Replaced = { key, to: x.to, from: entry[key], provenance: s.prov[at] };
        prov[at] = { by: 'ask', turnId: view.turnId, quote: x.quote };
        const q = questionOfKey(key);
        if (q) delete left[`${p.rid}/${q.id}`];
        return replaced;
      });
      const next = { ...s, draft, prov, left };
      return end(
        { state: 'used', say: checked.turn.say, drafted },
        { draft, prov, left, revision: s.revision + 1, suggested: suggestion(next, p.rid, ask) },
      );
    }),
  undo: (turnId) =>
    set((s) => {
      const turn = s.turns.find((t) => t.id === turnId);
      const i = turn ? s.rids.indexOf(turn.rid) : -1;
      if (!turn?.drafted || turn.undone || !s.draft || i < 0) return s;
      const draft = clone(s.draft);
      const r = draft.receivers[i] as Record<string, unknown>;
      const prov = { ...s.prov };
      let restored = 0;
      // A turn whose drafted answer comes back by this undo can be undone again
      const back = new Set<string>();
      for (const d of turn.drafted) {
        const at = `${turn.rid}/${d.key}`;
        const now = prov[at];
        // Only an answer that is still this turn's: a hand edit since is the person's, and a later turn's is that turn's
        if (!now || now.by !== 'ask' || now.turnId !== turnId) continue;
        restored += 1;
        if (d.from === undefined || d.from === null) delete r[d.key];
        else r[d.key] = d.from;
        if (d.provenance) prov[at] = d.provenance;
        else delete prov[at];
        if (d.provenance?.by === 'ask') back.add(d.provenance.turnId);
      }
      // Nothing of it was still this turn's: it stays as it was, and can be undone once its answer is back
      if (!restored) return s;
      return {
        draft,
        prov,
        turns: s.turns.map((t) =>
          t.id === turnId ? { ...t, undone: true } : back.has(t.id) ? { ...t, undone: false } : t,
        ),
        revision: s.revision + 1,
      };
    }),
  tookSuggestion: () => set({ suggested: null }),
  type: (rid, question, text) => set((s) => ({ typed: { ...s.typed, [`${rid}/${question}`]: text } })),
}));

/** The turn being read marked as dropped, so whatever comes back for it is ignored. */
function dropPending(s: SetupData): Partial<SetupData> {
  if (!s.pending) return {};
  const id = s.pending.turnId;
  return {
    pending: null,
    turns: s.turns.map((t) =>
      t.id === id ? { ...t, state: 'cancelled' as const, note: 'Dropped: nothing of it is used.' } : t,
    ),
  };
}

/** The question a turn suggested next, when it is an unanswered question of this receiver's checklist. */
function suggestion(
  s: SetupData,
  rid: string,
  q: SetupQuestion | undefined,
): { rid: string; question: QuestionId } | null {
  return q && statusOf(s, rid, q) === 'unanswered' ? { rid, question: q.id } : null;
}

/** The answers of the draft that Ask Shutter drafted and nobody has changed since, in the page's words. */
export function draftedAnswers(s: SetupData): DraftedAnswer[] {
  if (!s.draft) return [];
  const out: DraftedAnswer[] = [];
  for (const [at, p] of Object.entries(s.prov)) {
    if (p.by !== 'ask') continue;
    const [rid, key] = at.split('/');
    const r = receiverOf(s, rid);
    const q = questionOfKey(key);
    if (!r || !q) continue;
    out.push({
      rid,
      receiver: r.name,
      key,
      label: q.short,
      value: answerText(q, r),
      quote: p.quote,
      consequence: consequence(q, r, s.draft),
    });
  }
  return out;
}

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
    useSetup.setState({ ...EMPTY, epoch: ++epochs, revision: useSetup.getState().revision + 1 }),
  );

/** For tests: no draft, no hand-over. */
export function resetSetupForTests(): void {
  nextRid = 1;
  useSetup.setState({ ...EMPTY });
}
