import { create } from 'zustand';
import { SIGNED_OUT } from '@/api/hooks';

/**
 * The Ask Shutter panel's state: whether it is open, remembered per tab (`sessionStorage`, so a reload keeps it and
 * another tab starts closed), the case whose first suggested question it asks when "Ask about this case" opened it, and
 * the questions asked about each page while the tab lives, so a page's thread is there again when the reader comes back.
 * Nothing here is sent anywhere: the questions and answers live on the server, or in the trial's mock.
 */

export const ASSISTANT_OPEN_KEY = 'shutter:assistant:open';

/** Whether this tab last left the panel open; storage can refuse, and then it starts closed. */
function storedOpen(): boolean {
  try {
    return window.sessionStorage.getItem(ASSISTANT_OPEN_KEY) === '1';
  } catch {
    return false;
  }
}

function remember(open: boolean): void {
  try {
    if (open) window.sessionStorage.setItem(ASSISTANT_OPEN_KEY, '1');
    else window.sessionStorage.removeItem(ASSISTANT_OPEN_KEY);
  } catch {
    // Storage refused: the panel still opens and closes, and the next load starts closed
  }
}

/**
 * One question of a page that "Ask Shutter about this" opened the panel on: the page's name, the control it is about
 * (`id`, which the button carries too, so focus goes back to it when the panel closes), the question as Ask Shutter is
 * asked it, the answer on the page when it was asked and what that answer does there, both in the page's own words, and
 * the written explanation shown wherever no live answer can be given. The page builds it; nothing in it is sent but the
 * question and the context (screen.ts, `withFocus`).
 */
export interface PageFocus {
  page: string;
  id: string;
  /** What the question is, as the panel heads it: "Its tier: Records Out". */
  title: string;
  /** The question asked live. */
  question: string;
  /** The answer on the page, in its words: "Tier 2, operations". */
  answer: string;
  /** What that answer does, from the page's own rules, not from a model. */
  consequence: string;
  /** The written explanation. */
  written: string;
}

/** Whether two of a page's questions read the same, field by field. */
const sameFocus = (a: PageFocus, b: PageFocus) =>
  (Object.keys(a) as (keyof PageFocus)[]).every((k) => a[k] === b[k]) &&
  Object.keys(a).length === Object.keys(b).length;

/** A question asked about a page in this tab: its id on the server (or in the mock) and its words. */
export interface PageAsked {
  questionId: string;
  question: string;
}

interface AssistantState {
  open: boolean;
  /** The case whose first suggested question the panel asks as it opens, once, or null. */
  autoAsk: string | null;
  /** The questions asked about each page (by the page's name), oldest first. */
  threads: Record<string, PageAsked[]>;
  /** The page's question the panel was opened on by "Ask Shutter about this", until the panel closes. */
  focus: PageFocus | null;
  setOpen: (open: boolean) => void;
  toggle: () => void;
  /** Opens the panel from a case's "Ask about this case": the panel then asks the case's first suggested question. */
  openForCase: (caseId: string) => void;
  /** The panel took the auto-ask: it is not asked again. */
  tookAutoAsk: () => void;
  /** Opens the panel on one of the page's questions ("Ask Shutter about this"). */
  askAbout: (focus: PageFocus) => void;
  /**
   * Keeps the question in focus in step with the page while the panel is open on it: the same page and control, with
   * the answer and what it does as the page has them now. Any other question, or a closed panel, is left as it is.
   */
  followFocus: (focus: PageFocus) => void;
  addAsked: (page: string, asked: PageAsked) => void;
}

export const useAssistant = create<AssistantState>((set, get) => ({
  open: typeof window === 'undefined' ? false : storedOpen(),
  autoAsk: null,
  threads: {},
  focus: null,
  setOpen: (open) => {
    remember(open);
    set(open ? { open } : { open, autoAsk: null, focus: null });
  },
  toggle: () => get().setOpen(!get().open),
  openForCase: (caseId) => {
    remember(true);
    set({ open: true, autoAsk: caseId });
  },
  tookAutoAsk: () => set({ autoAsk: null }),
  askAbout: (focus) => {
    remember(true);
    set({ open: true, focus });
  },
  followFocus: (focus) =>
    set((s) =>
      s.open && s.focus?.page === focus.page && s.focus.id === focus.id && !sameFocus(s.focus, focus)
        ? { focus }
        : s,
    ),
  addAsked: (page, asked) =>
    set((s) => ({ threads: { ...s.threads, [page]: [...(s.threads[page] ?? []), asked] } })),
}));

/**
 * A sign-out forgets the questions asked in this tab, as the guide does: on a shared tab the next person to sign in never
 * sees the last one's questions (whose answers only the asker may read). The panel's open or closed state stays, like the
 * appearance.
 */
if (typeof window !== 'undefined')
  window.addEventListener(SIGNED_OUT, () =>
    useAssistant.setState({ threads: {}, autoAsk: null, focus: null }),
  );

/** For tests: the panel closed, nothing to auto-ask, no threads, no question in focus. */
export function resetAssistantForTests(): void {
  remember(false);
  useAssistant.setState({ open: false, autoAsk: null, threads: {}, focus: null });
}
