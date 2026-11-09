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
  setOpen: (open: boolean) => void;
  toggle: () => void;
  /** Opens the panel from a case's "Ask about this case": the panel then asks the case's first suggested question. */
  openForCase: (caseId: string) => void;
  /** The panel took the auto-ask: it is not asked again. */
  tookAutoAsk: () => void;
  addAsked: (page: string, asked: PageAsked) => void;
}

export const useAssistant = create<AssistantState>((set, get) => ({
  open: typeof window === 'undefined' ? false : storedOpen(),
  autoAsk: null,
  threads: {},
  setOpen: (open) => {
    remember(open);
    set(open ? { open } : { open, autoAsk: null });
  },
  toggle: () => get().setOpen(!get().open),
  openForCase: (caseId) => {
    remember(true);
    set({ open: true, autoAsk: caseId });
  },
  tookAutoAsk: () => set({ autoAsk: null }),
  addAsked: (page, asked) =>
    set((s) => ({ threads: { ...s.threads, [page]: [...(s.threads[page] ?? []), asked] } })),
}));

/**
 * A sign-out forgets the questions asked in this tab, as the guide does: on a shared tab the next person to sign in never
 * sees the last one's questions (whose answers only the asker may read). The panel's open or closed state stays, like the
 * appearance.
 */
if (typeof window !== 'undefined')
  window.addEventListener(SIGNED_OUT, () => useAssistant.setState({ threads: {}, autoAsk: null }));

/** For tests: the panel closed, nothing to auto-ask, no threads. */
export function resetAssistantForTests(): void {
  remember(false);
  useAssistant.setState({ open: false, autoAsk: null, threads: {} });
}
