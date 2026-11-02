/**
 * What the trial answered in this browser, and what the browser refused: every call the recorded mock answered
 * (method, path, status, time; the last few hundred), the network requests the guard refused, and the
 * Content-Security-Policy violations the page reported. The banner's "What's different?" shows the counts, and the
 * tests read them through `window.shutterTrial.journal` (set in trial pages only). It holds no API data.
 */
export interface JournalEntry {
  method: string;
  path: string;
  status: number;
  at: string;
}

export interface JournalCounts {
  /** Calls the mock answered that read (GET, HEAD). */
  reads: number;
  /** Calls the mock answered that would change something on a live system. */
  actions: number;
  /** Requests to `/api/shutter` the guarded `fetch` refused. */
  refused: number;
  /** Network requests the browser itself refused (the page's `connect-src 'none'`). */
  violations: number;
}

/** When and how the trial's recording was made (fixtures.json), once the trial's mock has loaded. */
export interface Recording {
  at: string;
  source: string;
}

const KEEP = 400;
let entries: JournalEntry[] = [];
let counts: JournalCounts = { reads: 0, actions: 0, refused: 0, violations: 0 };
let recording: Recording | null = null;
const listeners = new Set<() => void>();
const changed = () => listeners.forEach((l) => l());

export const journal = {
  /** A call the recorded mock answered. */
  add(method: string, path: string, status: number) {
    const read = method === 'GET' || method === 'HEAD';
    entries = [...entries.slice(-(KEEP - 1)), { method, path, status, at: new Date().toISOString() }];
    counts = { ...counts, [read ? 'reads' : 'actions']: counts[read ? 'reads' : 'actions'] + 1 };
    changed();
  },
  /** A request the guarded `fetch` refused. */
  refuse() {
    counts = { ...counts, refused: counts.refused + 1 };
    changed();
  },
  /** A network request the browser refused under the page's policy. */
  violation() {
    counts = { ...counts, violations: counts.violations + 1 };
    changed();
  },
  setRecording(r: Recording) {
    recording = r;
    changed();
  },
  entries: (): readonly JournalEntry[] => entries,
  counts: (): JournalCounts => counts,
  recording: (): Recording | null => recording,
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
  /** For tests only: an empty journal. */
  clear() {
    entries = [];
    counts = { reads: 0, actions: 0, refused: 0, violations: 0 };
    recording = null;
    changed();
  },
};

export type Journal = typeof journal;
