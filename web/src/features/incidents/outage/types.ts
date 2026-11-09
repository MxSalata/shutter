/** A receiver outage and its watched receivers as the outage routes give them (CONTRACTS 17). */

export interface OutageRow {
  headerId: string;
  controlId: string;
  timeCreated: string;
  status: string;
  attempts: string;
  reason: string;
  patient?: { id: string; authority: string } | null;
  sibling?: { headerId: string; status: string; at: string } | null;
}

export interface OutageReading {
  receiver: string;
  namespace?: string | null;
  item?: string | null;
  reading: string;
  status?: string | null;
  adapterState?: string | null;
  queue?: number | string | null;
  retry?: string | null;
  checkedAt?: string | null;
}

export interface OutageSet {
  status: 'computed' | 'not_computed' | 'withheld' | string;
  reason?: string | null;
  digest?: string | null;
  computedAt?: string | null;
}

export interface Outage {
  id: string;
  receiver: string;
  namespace?: string | null;
  item?: string | null;
  state: string;
  kind?: string | null;
  openedAt?: string | null;
  closedAt?: string | null;
  pausedUntil?: string | null;
  readings?: OutageReading | null;
  alerts: { at: string; kind: string; text: string }[];
  lists: { queued: OutageRow[]; offered: OutageRow[]; reached: OutageRow[]; refused: OutageRow[] };
  openCases: { caseId: string; reason: string; owner: string }[];
  version: number;
  set: OutageSet;
  approvable: boolean;
  acts: string[];
  outcome?: string | null;
  words: { first?: string | null; do?: string | null; call?: string | null; critical?: string | null };
}

export interface OutageList {
  items: Outage[];
  receivers: OutageReading[];
}
