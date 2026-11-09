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
  /** The acts a person may take on this message alone (v1.53): `handled_by_hand` on an offered row where duplicates are unknown. */
  acts?: string[];
  /** On a row of `lists.closed`: `already_delivered` or `handled_by_hand`; null elsewhere. */
  closure?: string | null;
  closedBy?: string | null;
  closedAt?: string | null;
}

/**
 * One row of the resend ledger (CONTRACTS 17.8): a message an approval sent, or one a person closed by hand. `closure` is
 * `sent`, `already_delivered`, `handled_by_hand`, `failed` or `unknown`, and null while approved, sending or stopped.
 */
export interface Resend {
  runId: string;
  position: number;
  headerId?: string | null;
  controlId?: string | null;
  newHeaderId?: string | null;
  /** approved, sending, completed, failed, closed_as_present, handled_by_hand, stopped or unknown. */
  state: string;
  closure?: string | null;
  words?: string | null;
  /** The approver, or the person who recorded a hand closure. */
  by?: string | null;
  /** When the row ended, or when it started while sending. */
  at?: string | null;
  caseId?: string | null;
  /**
   * Why the recovery control halted the run before this row was sent (CONTRACTS 18): recovery_stopped, recovery_shadow,
   * control_unavailable or control_unreadable; null otherwise, and absent from a server before it.
   */
  halt?: string | null;
}

/** The one approval of an offered set: who gave it, when, how long it stands before the first send, and its note. */
export interface OutageApproval {
  id: string;
  by: string;
  givenAt: string;
  goodUntil?: string | null;
  digest?: string | null;
  note?: string | null;
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
  lists: {
    queued: OutageRow[];
    offered: OutageRow[];
    reached: OutageRow[];
    refused: OutageRow[];
    /** v1.53: messages closed with no send of their own (already delivered, or handled by hand). */
    closed?: OutageRow[];
  };
  openCases: { caseId: string; reason: string; owner: string }[];
  version: number;
  set: OutageSet;
  approvable: boolean;
  approval?: OutageApproval | null;
  sentByShutter?: number;
  acts: string[];
  /** v1.53: the ledger's rows for this outage, each run in position order. */
  resends?: Resend[];
  outcome?: string | null;
  words: { first?: string | null; do?: string | null; call?: string | null; critical?: string | null };
}

export interface OutageList {
  items: Outage[];
  receivers: OutageReading[];
}
