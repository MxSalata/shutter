/**
 * The REST API's shapes (docs/CONTRACTS.md, section 5): the store's JSON projections, camelCase. Fields the store
 * keeps as JSON text (a plan, a run's result, the gate's checks) may arrive as text or as JSON; `parseJson` in
 * lib/json.ts reads either.
 */

export type CaseState =
  | 'detected'
  | 'collecting'
  | 'investigating'
  | 'grouped'
  | 'proposed'
  | 'gated'
  | 'rehearsing'
  | 'awaiting_approval'
  | 'approved'
  | 'executing'
  | 'verifying'
  | 'resolved'
  | 'blocked'
  | 'escalated'
  | 'failed';

export const CLOSED_STATES: readonly CaseState[] = ['resolved', 'blocked', 'escalated', 'failed'];

export type Mode = 'board' | 'single' | 'rules' | 'policy';

export type Disposition =
  'resend' | 'reconcile' | 'superseded' | 'more_evidence' | 'escalate' | 'handled_by_hand' | 'abandoned';

/**
 * What the signed-in user may do (CONTRACTS 5, since v1.34): the resources the user holds, so the app shows only what
 * the user may use. The public demo's role approves and operates, and neither configures the site nor runs scenarios.
 */
export interface Can {
  operate: boolean;
  approve: boolean;
  /** Saving the site profile or the agent library, importing a schema, annotating a production review. */
  configure: boolean;
  /** Running and resetting scenarios. */
  scenarios: boolean;
  /**
   * Spending the day's model budget (the resource Shutter_LiveAgents, CONTRACTS 5): convening the board on a case, and
   * asking a question that no recording answers. The public demo's own user has it not; a judge, an operator and an
   * approver have it.
   */
  liveAgents: boolean;
}

/** One of the roles Shutter installs, as `GET /access` reads it (CONTRACTS 5): whether it is defined on this instance. */
export interface AccessRole {
  role: string;
  installed: boolean;
}

/** What a person can do in Shutter, as one row of the access table. */
export type AccessRowId =
  'view' | 'approve' | 'scenarios' | 'liveAgents' | 'configure' | 'inbox' | 'guide' | 'trace' | 'publisher';

export interface AccessRow {
  id: AccessRowId;
  /** The resources it needs: one of the alternatives, each a list of `resource:permission` all of which are needed. */
  needs: string[][];
  /** False when this instance has nothing to hold: the Shutter in IRIS page off a demo, the publisher off AI Hub. */
  available: boolean;
  /** Each role's answer, by role name, from the role's resources and its granted roles'. */
  roles: Record<string, boolean>;
  /** The signed-in user's own answer, from the resources they hold. */
  you: boolean;
}

/**
 * `GET /access` (CONTRACTS 5): what each of Shutter's roles may do beside what the signed-in user may, read only. It names
 * roles and resources, never a user. The roles' columns come from the record the install, the portal's hardening and each
 * start of the production write (`read` says `recorded`, with `recordedAt`), or from Security.Roles itself for a caller
 * who may read it (`now`); `none` means no record yet, and every role then reads as not installed. The user's own column
 * is always read now, from the resources they hold.
 */
export interface AccessReport {
  demo: boolean;
  /** The public demo's portal hardening is on: the Management Portal's pages need the resource Shutter_Portal. */
  portalHardened: boolean;
  read: 'now' | 'recorded' | 'none';
  recordedAt?: string;
  roles: AccessRole[];
  rows: AccessRow[];
}

export interface Me {
  username: string;
  operator: boolean;
  approver: boolean;
  /** Absent from a server older than v1.34: `resolveCan` (api/can.ts) derives it from `operator` and `approver`. */
  can?: Partial<Can>;
}

// ---- scenarios (5.2): the runner's own JSON, so its fields stay as scenarios.json writes them ----

export interface ScenarioStep {
  file?: string;
  path?: string;
  expect?: string;
  fault?: string;
  operation_key?: string;
  wait?: number;
  wait_for_state?: string;
  timeout?: number;
  capabilities?: Record<string, unknown>;
  /** The receivers a fault applies to, when it is more than the one (S22). */
  receivers?: string[];
  /** A change made by hand in the receiver itself, not through the feed (S20). */
  manual?: { encounter_id: string; event: string; ward: string; event_time: string };
}

export interface ScenarioExpected {
  /** Its other fields describe the case of `failed_operation_key`; the story opens other cases too. */
  case_by_key?: boolean;
  /** Absent when the expectations are per receiver (by_receiver). */
  disposition?: string;
  acceptable?: string[];
  write: boolean;
  final_state: string;
  final_ward: string | null;
  failed_operation_key: string;
  blocked_by?: string;
  /** The reason code the case should end on, where it has one (S20, S23c, S25). */
  final_reason?: string;
  injected_note?: string;
  other_encounter?: string;
  /** The modes the scenario is defined for, when not all of them: in another mode its card doesn't apply. */
  modes?: Mode[];
  /** An incident scenario: many failures to one receiver, settled as one chain per encounter (S11, S12). */
  incident?: boolean;
  /** An incident scenario's encounters, each with the writes its chain makes and where it ends. */
  encounters?: { encounter: string; writes: number; final_state: string; final_ward: string | null }[];
  /** A mode's own additions to the expected outcome, which replace the fields they name in that mode (S21's rules). */
  by_mode?: Partial<Record<Mode, Partial<ScenarioExpected>>>;
  /**
   * One failure at several receivers (S22, v1.25): what each receiver's case should end in, by the receiver's name.
   * `outcome` names the catalogue outcome its plan takes, such as correct_history.
   */
  by_receiver?: Record<
    string,
    { disposition: string; outcome?: string; write: boolean; final_state: string; final_ward: string | null }
  >;
}

export interface ScenarioRun {
  scenario: string;
  mode: Mode;
  startedAt: string;
  /** queued: the scenario player has the run and will start it; then as Runner.Status reports. */
  state: 'queued' | 'running' | 'done' | 'failed' | 'interrupted';
  queuedAt?: string;
  files: string[];
  timeouts: string[];
  step?: string;
  finishedAt?: string;
  error?: string;
}

export interface Scenario {
  id: string;
  title: string;
  summary: string;
  steps: ScenarioStep[];
  expected: ScenarioExpected;
  latestCase: { caseId: string; state: CaseState; disposition: string; headline: string } | null;
}

export interface ScenarioList {
  scenarios: Scenario[];
  run: ScenarioRun | null;
}

export interface RunStarted {
  scenario: string;
  mode: Mode;
  startedAt: string;
  files: string[];
}

// ---- cases (5.3) ----

export interface CaseSummary {
  caseId: string;
  state: CaseState;
  version: number;
  mode: Mode;
  scenario: string;
  disposition: string;
  headline: string;
  event: string;
  ward: string;
  eventTime: string;
  encounterId: string;
  openedAt: string;
  updatedAt: string;
  closedAt: string;
  ensSessionId: string;
  workflowSessionId: string;
  /**
   * How the delivery failed (delivery_failed, uncertain, unmappable, withheld for a merge or a cancel never sent, or
   * unreadable: held because its HL7 schema is not loaded and the site prevents failures).
   */
  failureKind: string;
  /**
   * The receiver (the production item) the failed delivery went to: a case is one failed delivery to one receiver
   * (v1.25). Absent from cases recorded before the server sent it, which all went to the bed manager.
   */
  receiver?: string;
  /** Attempts that reached the receiver and may have landed (applied, already committed, uncertain), when sent. */
  writes?: number;
  /** The latest verification's outcome, or "" when there is none, when sent. */
  verification?: string;
  /** The incident that holds the case, when one does (CONTRACTS 7.5). */
  incidentId?: string;
  /**
   * Who made the current plan, as the plan's `createdBy` names it: `run:<id>` for an agent run (the coordinator's,
   * or the single investigator's), `policy:<entry>` for the catalogue and the site's policy, `rules` for rules alone,
   * `withheld` for a withheld operation no single catalogue entry matched (no agent runs; a person decides). Sent only
   * when the case has a plan; a server that does not send it leaves the list to read the case's state and mode.
   */
  planCreatedBy?: string;
  /** The Ens.MessageHeader id of the message whose delivery failed: Shutter's own copy for a forwarded case. */
  sourceHeaderId?: string;
  /**
   * Where the original message lives when another production forwarded the case (CONTRACTS 11): its namespace, the
   * production and the route (the item) that received it there, and its header id in that namespace. Empty or absent
   * for a case the feed in Shutter's own production opened.
   */
  sourceNamespace?: string;
  sourceProduction?: string;
  sourceRoute?: string;
  originHeaderId?: string;
  /** The bed within the ward (PV1-3) for an admission or a transfer, else null (CONTRACTS 11, v1.28). */
  bed?: string | null;
  /** The case this one waits on while the gate holds its write with WAITING_FOR_OCCUPANT_CASE (CONTRACTS 6.5, v1.28). */
  waitsOn?: string | null;
  /** The control id of the newer message it waits for under NEWER_MESSAGE_PENDING (CONTRACTS 6.5, v1.29). */
  waitsOnMessage?: string | null;
  /** The schema category whose absence holds the message, kind `unreadable` (CONTRACTS 11, v1.34); "" otherwise. */
  heldSchema?: string;
  /** Until when the receiver asked not to retry, its Retry-After on the failed delivery (CONTRACTS 1.1, v1.35). */
  retryAfterUntil?: string;
  /** The case whose board this one follows while that board runs, one board per failure signature (CONTRACTS 6.6, v1.35). */
  followsCase?: string;
  /** The failure signature this case led or followed a board for (CONTRACTS 6.6, v1.35). */
  leadSignature?: string;
}

export interface CaseList {
  items: CaseSummary[];
  total: number;
}

export interface CaseDetail extends CaseSummary {
  operationKey: string;
  /** No catalogue entry fitted the case: it is flagged as a candidate for a new entry (CONTRACTS 6.3). */
  candidateEntry?: boolean;
  failureText: string;
  /** The downstream system's answer to the failed delivery, when it gave one: its HTTP status and reason code. */
  failureHttpStatus?: number;
  failureReasonCode?: string;
  patientId: string;
  patientIdAuthority: string;
  /** A merge only (ADT^A40): the patient (MRG-1) and visit (MRG-5) merged into this one, and how many MRG groups. */
  priorPatientId?: string;
  priorPatientIdAuthority?: string;
  priorEncounterId?: string;
  mergeGroups?: number;
  sourceSystem: string;
  sourceMessageId: string;
  outcome: string;
  counts: {
    events: number;
    runs: number;
    findings: number;
    plans: number;
    approvals: number;
    attempts: number;
  };
  links: { visualTrace: string; workflowTrace: string };
  /** The case's place in its incident, when one holds it. */
  incident?: CaseIncident;
}

export interface CaseEvent {
  seq: number;
  at: string;
  kind: 'state' | 'note' | 'artifact' | 'error' | 'approval' | 'execution';
  fromState: string;
  toState: string;
  text: string;
  actor: string;
  ref: string;
  /** Set by the trial's mock on the events it replays from the recording after a trial approval; never by IRIS. */
  replayed?: boolean;
}

export interface SnapshotItem {
  seq: number;
  kind: string;
  source: string;
  /** Snake case, as Shutter.Store.Snapshot.Items() sends it. */
  observed_at: string;
  /** The observation's own digest, shown when the API sends one. */
  digest?: string;
  data: unknown;
}

export interface Snapshot {
  id: string | number;
  seq: number;
  digest: string;
  /** The digest of what a decision rests on, without the observation times (A7), when the API sends it. */
  materialDigest?: string;
  takenAt: string;
  freshUntil: string;
  summary: unknown;
  items: SnapshotItem[];
}

export interface ToolCall {
  seq: number;
  /**
   * When the call was logged, to the millisecond: the bridge's audit policy writes the row once the tool has answered,
   * so the call ran from `at` minus `durationMs` to `at`.
   */
  at: string;
  name: string;
  arguments: unknown;
  durationMs: number;
  ok: boolean;
  resultPreview: string;
  error?: string;
  /** Refused by the authorisation policy before it ran (v1.35): `ok` is false and `durationMs` 0, nothing ran. */
  denied?: boolean;
}

export interface Finding {
  runId?: string | number;
  role: string;
  memberCode: string;
  disposition: string;
  confidence: number | string;
  summary: string;
  findings: unknown;
  createdAt: string;
}

export interface AgentRun {
  id?: string | number;
  role: string;
  memberCode: string;
  agentClass: string;
  mode: string;
  model: string;
  status: string;
  startedAt: string;
  durationMs: number;
  promptTokens: number;
  completionTokens: number;
  cacheReadTokens: number;
  cacheCreationTokens: number;
  iterations: number;
  toolCallCount: number;
  ensMessageId: string;
  result: unknown;
  content: string;
  error: string;
  costUsd: number | string;
  member: { code: string; name: string; perspective: string } | null;
  finding: Finding | null;
  toolCalls: ToolCall[];
  /** The run's message in the Management Portal, when the API gives it. */
  messageLink?: string;
  /** The snapshot the run read: one board pass's runs share it. */
  snapshotId?: string | number;
  /** The question the run answered (Ask about this case), empty for an investigation's run. */
  questionId?: string | null;
  /**
   * The run's own clock (CONTRACTS 9, v1.35): the start to the millisecond, beside `startedAt` (to the second), and
   * AI Hub's counters when the build gives them (time inside the model's calls, time inside the tools, reasoning
   * tokens). A replay, or a build that gives none, leaves the counters empty, never zero.
   */
  startedAtMs?: string | null;
  llmMs?: number | null;
  toolMs?: number | null;
  reasoningTokens?: number | null;
}

// ---- precedents (CONTRACTS 6.4, v1.35) ----

/**
 * What approvers decided before on the same conditions at the same receiver, as every snapshot summary carries it
 * (`precedents`) and GET /cases/{id}/precedents gives it now: the active rows of the last `windowDays` days.
 * `samePolicy` says whether the last decision was taken under the policy and site profile versions in force now.
 */
export interface PrecedentSummary {
  approved: number;
  rejected: number;
  lastDecision: '' | 'approved' | 'rejected';
  lastApprover: string;
  lastAt: string;
  lastCaseId: string;
  samePolicy: boolean;
  windowDays: number;
  signature: string;
  /** The collector could not read them. */
  error?: string;
}

/** One person's decision on these conditions at this receiver; a retired one stays, with `active` false. */
export interface Precedent {
  id: string | number;
  caseId: string;
  receiver: string;
  signature?: string;
  conditions?: unknown;
  catalogueEntry?: string;
  catalogueOutcome?: string;
  disposition?: string;
  planDigest?: string;
  approver: string;
  /** approved: the person approved and the write was verified at the receiver; rejected: the person rejected the plan. */
  decision: 'approved' | 'rejected';
  policyVersion?: string;
  siteProfileVersion?: string | number;
  catalogueVersion?: string;
  createdAt: string;
  active: boolean;
  retiredAt?: string;
  retiredBy?: string;
  retiredReason?: string;
}

/** GET /cases/{id}/precedents: the case's receiver and conditions, the summary now, and every row, newest first. */
export interface PrecedentsView {
  receiver: string;
  conditions: unknown;
  summary: PrecedentSummary;
  precedents: Precedent[];
}

export interface Plan {
  id?: string | number;
  version: number;
  digest: string;
  disposition: string;
  actionType: string;
  operationKey: string;
  expectedVersion: number | string;
  payloadDigest: string;
  preconditions: unknown;
  evidenceRefs: unknown;
  disagreements: unknown;
  summary: string;
  plan: unknown;
  createdAt: string;
  createdBy: string;
  /** The scenario catalogue's entry the plan follows, when it names one (E1 to E19). */
  catalogueEntry?: string;
  /** "preferred", or the alternative taken, with the reason. */
  outcome?: string;
  why?: string;
}

export interface GateCheck {
  check: string;
  result: 'pass' | 'block' | 'unknown';
  reason_code: string;
  detail: string;
}

export interface GateDecision {
  stage: 'proposal' | 'approval' | 'dispatch';
  outcome: 'pass' | 'block' | 'unknown';
  policyVersion: string;
  checks: GateCheck[] | string;
  summary: string;
  at: string;
}

export interface Rehearsal {
  at: string;
  httpStatus: number;
  wouldApply: boolean;
  reason: string;
  receiverVersion: number | string;
  response: unknown;
}

/**
 * The steps that correct a history-of-record receiver's history by hand, on the plan of a case escalated with the
 * outcome correct_history (CONTRACTS 10, v1.23): built from the case and its snapshot alone.
 */
export interface CorrectionSteps {
  receiver: string;
  system?: string;
  category?: string;
  encounter?: string;
  missing?: {
    event?: string;
    ward?: string;
    event_time?: string;
    source_message_id?: string;
    operation_key?: string;
    after?: string;
  };
  later?: { event?: string; ward?: string; event_time?: string }[];
  current?: { state?: string; ward?: string; version?: number | string };
  receipt?: string;
  steps: string[];
}

export interface PlanView {
  plan: Plan;
  gateDecisions: GateDecision[];
  rehearsal: Rehearsal | null;
}

export interface Approval {
  planDigest: string;
  snapshotDigest: string;
  policyVersion: string;
  expectedVersion: number | string;
  approver: string;
  decision: 'approved' | 'rejected';
  decidedAt: string;
  expiresAt: string;
  revoked: boolean;
  revokedAt: string;
  revokedBy: string;
  workflowTaskId: string;
  comment: string;
  /** What else the approval binds, when the API sends it: the receiver's epoch, the evidence and the site profile. */
  receiverEpoch?: number | string;
  materialDigest?: string;
  siteProfileVersion?: string;
  /** Set only on an approval given under an incident's: the incident plan's digest, and the entry and outcome it covered. */
  incidentPlanDigest?: string;
  boundEntry?: string;
  boundOutcome?: string;
}

export interface WorkflowTask {
  taskId: string;
  subject: string;
  actions: string;
  action: string;
  userName: string;
  role: string;
  complete: boolean;
  assignedTo: string;
  timeCreated: string;
  timeCompleted: string;
  /** The digest the decider named: empty while the task is open. */
  planDigest?: string;
}

export interface ApprovalsView {
  approvals: Approval[];
  tasks: WorkflowTask[];
}

export interface Attempt {
  at: string;
  operationKey: string;
  expectedVersion: number | string;
  httpStatus: number;
  outcome: string;
  receipt: unknown;
  response: unknown;
  error: string;
}

export interface Verification {
  at: string;
  /** failed: the receiver contradicts itself or the plan, a person must check; not_committed: the write did not land. */
  outcome: 'verified' | 'not_committed' | 'unresolved' | 'failed' | string;
  summary: string;
  detail: unknown;
}

export interface AttemptView {
  attempt: Attempt | null;
  verification: Verification | null;
}

export interface Closure {
  disposition: string;
  outcome: string;
  verification: Verification | null;
  verifiedEffects: unknown[];
  unverified: unknown[];
  actors: unknown[];
  policyVersion: string;
  closedAt: string;
}

export interface BlockedReason {
  code: string;
  title: string;
  prerequisite: string;
  nextAction: string;
  owner: string;
  reevaluateWhen: string;
  text: string;
  checks?: GateCheck[];
}

export interface BlindResendPreview {
  wouldApply: boolean;
  /** would_apply or would_not_apply for a dry run the receiver rolled back; anything else is not one. */
  outcome: string;
  /** True when the receiver wrote the preview: it does not honour dry_run, and the operation is now in effect. */
  applied: boolean;
  reason: string;
  encounterAfter: unknown;
  /** The receiver version and epoch the dry run was checked against. */
  checkedAgainst: { version: number | null; epoch: number | null };
  /** A preview is conditional on no version. */
  expectedVersion: null;
  note: string;
}

export interface ApprovalDecision {
  decision: 'approve' | 'reject';
  planDigest: string;
  expectedVersion: number;
  comment: string;
}

// ---- incidents (CONTRACTS 7.5) ----

export type IncidentState = 'open' | 'classified' | 'awaiting_approval' | 'releasing' | 'closed';

export interface IncidentProgress {
  chains: number;
  cases: number;
  byKind: Record<string, number>;
  byState: Record<string, number>;
}

/** The store's projection of an incident: fields with no value are left out. */
export interface IncidentSummary {
  incidentId: string;
  /** The production item the failures went to. */
  receiver: string;
  mode: Mode;
  state: IncidentState;
  openedAt: string;
  intakeClosedAt?: string;
  closedAt?: string;
  threshold?: number;
  windowMinutes?: number;
  quietSeconds?: number;
  lastFailureAt?: string;
  planDigest?: string;
  receiverEpoch?: number;
  catalogueVersion?: string;
  profileVersion?: string;
  policyVersion?: string;
  /** How the policy chains were authorised: automatic, approval, per_chain, approval+per_chain or none. */
  policy?: string;
  approvedBy?: string;
  approvedAt?: string;
  approvalDecision?: string;
  approvalComment?: string;
  approvalTaskId?: string;
  workflowSessionId?: string;
  summary?: string;
  version?: number;
  progress?: IncidentProgress;
}

export interface IncidentList {
  items: IncidentSummary[];
  total: number;
}

/** One failed operation of a chain, in event order. */
export interface ChainItem {
  position: number;
  caseId: string;
  event: string;
  eventTime: string;
  operationKey: string;
  /** The catalogue entry the case matched when the chain formed, its outcome and who decides it. */
  entry: string;
  outcome: string;
  decides: string;
  /** The receiver version the item goes at: the previous item's verified version (null: fresh evidence decides). */
  expectedVersion: number | null;
  verifiedVersion: number | null;
  /** pending, released, resolved, blocked, escalated, failed, stopped (never released). */
  state: string;
  caseState: CaseState;
  caseHeadline: string;
  /** What the released case matched on its fresh evidence. */
  releaseEntry?: string;
  releaseOutcome?: string;
  releasedAt?: string;
  closedAt?: string;
}

export interface ChainApproval {
  by: string;
  at: string;
  decision: string;
  comment: string;
  taskId: string;
}

/** The failed operations for one encounter, oldest event first (CONTRACTS 7.1). */
export interface Chain {
  chainId?: string | number;
  seq: number;
  encounterId: string;
  patientId?: string;
  /** single, ordered or interleaved. */
  kind: string;
  /** policy (the catalogue settles every item), board or person. */
  decides: string;
  /** automatic, approval or per_chain for a policy chain; path for one whose cases run their own path. */
  policy: string;
  entries?: string;
  /** pending, awaiting_approval, approved, rejected, releasing, resolved, stopped, escalated. */
  state: string;
  outcome?: string;
  firstExpectedVersion?: number | string;
  /** The item that stopped the chain. */
  stoppedAt?: number;
  approval?: ChainApproval;
  items: ChainItem[];
}

export interface IncidentApproval {
  scope: 'incident' | 'chain';
  seq?: number;
  by: string;
  at: string;
  decision: string;
  comment: string;
  taskId: string;
  planDigest: string;
}

export interface IncidentDetail extends IncidentSummary {
  chains: Chain[];
  /** The incident's plan (CONTRACTS 7.2): every chain with its kind, entry, outcome and items in order. */
  plan: unknown;
  approvals: IncidentApproval[];
  tasks: WorkflowTask[];
  links?: { workflowTrace?: string };
}

export interface IncidentEvent {
  at: string;
  kind: string;
  text: string;
  actor: string;
}

export interface IncidentDecision {
  decision: 'approve' | 'reject';
  planDigest: string;
  comment: string;
}

/** A case's place in its incident, in the store's snake case. */
export interface CaseIncident {
  incident_id: string;
  incident_state: IncidentState;
  chain_seq?: number;
  position?: number;
  chain_kind?: string;
  decides?: string;
  chain_policy?: string;
  item_state?: string;
  expected_version?: number;
}

// ---- escalations to the people who correct systems by hand (T29) ----

export interface Escalation {
  caseId: string;
  seq: number;
  /** draft, queued, sent, failed, cancelled. */
  state: string;
  teamId?: string;
  teamName?: string;
  /** Addresses separated by commas. */
  to?: string;
  cc?: string;
  subject: string;
  body: string;
  /** What a send names, so what goes is what the person read. */
  bodyDigest: string;
  snapshotDigest?: string;
  draftedBy?: string;
  draftedAt?: string;
  editedBy?: string;
  editedAt?: string;
  sentBy?: string;
  sentAt?: string;
  /** smtp, or file when no mail server is configured. */
  transport?: string;
  result?: string;
  /** When the retention task removed the text: body is then empty, and bodyDigest is what was sent. */
  purgedAt?: string;
}

export interface SiteTeam {
  id: string;
  name: string;
  mailbox: string;
  cc?: string[];
  /** The receivers (production items) whose cases this team corrects. */
  receivers?: string[];
  /** The sending applications (MSH-3) whose merges this team decides, such as PAS; checked before receivers. */
  sources?: string[];
  [key: string]: unknown;
}

// ---- the site profile (CONTRACTS 6.4) ----

export type ChainPolicy = 'automatic' | 'approval' | 'per_chain' | 'board';
export type ChainKind = 'single' | 'ordered' | 'interleaved';

/** A receiver in the site profile: the induction answers, and the receiver description the core reads its paths from. */
/** What kind of system a receiver is (CONTRACTS 6.4, v1.23); an entry without one is current_state. */
export type ReceiverCategory = 'current_state' | 'history_of_record' | 'orders_results';

export interface SiteReceiver {
  name: string;
  system?: string;
  /** The receiver's category, asked at onboarding; it derives the receiver's history policy. */
  category?: ReceiverCategory | string;
  /** Overrides the policy the category derives: current (keep what is current) or correct (correct the history). */
  history_policy?: 'current' | 'correct' | string;
  /** A demo receiver's namespace, where the scenario runner resets it and sets its faults (v1.25). */
  demo?: { namespace?: string };
  tier: number;
  applies?: string;
  resend_timestamp?: string;
  cancels?: boolean;
  /** Whether the receiver takes merges (ADT^A40); a merge still needs the site's merges: allowed. */
  merges?: boolean;
  api?: Record<string, string>;
  features?: Record<string, boolean>;
  [key: string]: unknown;
}

/** The profile as stored (snake case, as knowledge/site/profile.json writes it). */
export interface SiteProfile {
  version?: number;
  receivers: SiteReceiver[];
  /** Deprecated since v1.23: read only for a receiver entry with neither a category nor its own history policy. */
  history_policy?: string;
  authoritative_source?: string;
  unconditional_resend?: string;
  /** forbidden (the default: every merge goes to the PAS team) or allowed. */
  merges?: string;
  policy: Record<string, Partial<Record<ChainKind, string>>>;
  /** close_needs_approver: closing a case by hand needs an approver (the two-person rule); off when absent. */
  approvers?: { role?: string; escalation?: string; close_needs_approver?: boolean };
  incident?: {
    threshold?: number;
    window_minutes?: number;
    quiet_seconds?: number;
    max_intake_seconds?: number;
  };
  /** Who corrects the systems by hand when Shutter can't, and where their email goes (T29). */
  teams?: SiteTeam[];
  mail?: { from?: string; allowed_domains?: string[] };
  /** What may leave IRIS for a model beyond tokens and flags (CONTRACTS 9). */
  model_content?: { free_text?: boolean };
  /**
   * The zone of times the feed sends without an offset: an IANA name or a fixed offset (CONTRACTS 6.4); and whether the
   * feed is held while a message's HL7 schema category is not loaded here ("prevent failures", default false); how far
   * apart two sources' events still count as simultaneous; and whether an automatic release needs its source proved.
   */
  feed?: {
    time_zone?: string;
    prevent_failures?: boolean;
    source_skew_seconds?: number;
    prove_origin?: boolean;
  };
  /** How rigid the check of further messages for the patient is (CONTRACTS 6.5). Absent means stop and person. */
  further_messages?: {
    in_patient_movement?: 'stop' | 'show';
    admission_not_found?: 'person' | 'policy';
    scan_seconds?: number;
  };
}

/** GET /site-profile: the profile in force and its store version, which a PUT sends back as expectedVersion. */
export interface SiteProfileView {
  profile: SiteProfile;
  version: number;
  /** api for a profile saved through the API; defaults, or the seed file's path, for the shipped answers. */
  source: string;
  updatedAt: string;
  updatedBy: string;
  catalogueEntries: number;
}

export interface SiteProfileVersionEntry {
  version: number;
  source: string;
  updatedAt: string;
  updatedBy: string;
  profile?: SiteProfile;
}

// ---- library, settings, costs, health (5.4) ----

export interface LibraryMember {
  code: string;
  name: string;
  description: string;
  perspective: string;
  role: 'specialist' | 'coordinator' | 'generalist';
  agentClass: string;
  knowledgeCollection: string;
  configItem: string;
  terminalTool: string;
  enabled: boolean;
  inDefaultBoard: boolean;
  sort: number;
  configVersion: string;
}

/** A production item that runs an agent, with the settings it has (a replaying item has no model). */
export interface AgentItem {
  name: string;
  enabled?: boolean;
  agentClass?: string;
  /** auto, live, record or replay as set; effectiveMode is what auto resolves to now. */
  mode?: string;
  effectiveMode?: string;
  model?: string;
  providerConfig?: string;
  maxIterations?: number | string;
  tokenBudget?: number | string;
  /** Who answers a run that goes to a model: the API mimic while it is on, else the provider configuration; absent when replaying. */
  answeredBy?: string;
}

export interface ModelPrice {
  model: string;
  inputPerMTok: number;
  outputPerMTok: number;
  cacheReadPerMTok: number;
  cacheWritePerMTok: number;
  currency: string;
  source: string;
  asOf: string;
}

export interface Settings {
  /** The agent items' mode setting (auto by default) and whether a model provider is configured. */
  agentMode?: string;
  providerConfigured?: boolean;
  mode: Mode;
  /**
   * The mode a watched production's forwarded failures run in (CONTRACTS 6.3 and 11, v1.38): policy unless the site
   * set another, whatever mode the scenarios run in. Absent from an older server.
   */
  watchedMode?: Mode;
  scenario: string;
  resetAt: string;
  demo: boolean;
  agentItems: AgentItem[];
  prices: ModelPrice[];
  aiHubPresent: boolean;
  liveRunnerPresent: boolean;
  /**
   * The API mimic (tests/mock), a test fixture that answers live runs without a model: on, the configuration it set and
   * the model name it answers as. effectiveMode stays "live" for the items it answers.
   */
  mock?: boolean;
  mockConfig?: string;
  mockModel?: string;
  /** The live hospital (a public demo that plays a story on a timer): `{enabled: false}` on any other instance, absent from an older server. */
  live?: LiveStatus;
  /** The day's model budget (CONTRACTS 9, v1.34); absent from an older server. */
  budget?: Budget;
  /** Whether the feed is held while a message's schema is not loaded (the profile's `feed.prevent_failures`). */
  preventFailures?: boolean;
  /** The messages held because their schema category is not loaded here, by category. */
  heldMessages?: HeldMessages;
}

/**
 * `GET /settings` `budget`: what the live agents may spend between one 00:00 UTC and the next. `dailyUsd` 0 means no
 * cap. `perUserUsd` is each judge's share of it (0: none), and `spentByMeUsd` the signed-in user's live spend today.
 */
export interface Budget {
  dailyUsd: number;
  spentTodayUsd: number;
  exhausted: boolean;
  since?: string;
  resetsAt?: string;
  perUserUsd?: number;
  spentByMeUsd?: number;
  /** The signed-in user's share is used up (the day's cap may not be). */
  shareExhausted?: boolean;
  /** What the runs in flight have reserved against the cap, and how many there are (v1.35). */
  reservedUsd?: number;
  inFlight?: number;
  /** What the signed-in user's own runs in flight have reserved against their share (v1.35). */
  reservedByMeUsd?: number;
}

/**
 * `GET /settings` `live.agents` (CONTRACTS 9, v1.37): whether a live agent run can go out now, and if not why and until
 * when. `reason` `budget` is the day's cap or the caller's share spent (`until` is `budget.resetsAt`), `provider_auth` the
 * model provider refusing the key in the last 15 minutes (the public demo's key is switched off at a daily limit outside
 * Shutter; `until` is the next 00:00 UTC), null while live runs can go. `until` is an ISO UTC time, null when none is
 * given; `detail` is the server's sentence, for Technical. Absent from an older server: the app then reads the budget.
 * A refused live call answers `409 live_unavailable` with the same object as `live`.
 */
export interface LiveAgents {
  available: boolean;
  reason?: 'budget' | 'provider_auth' | null;
  until?: string | null;
  detail?: string;
}

/**
 * `GET /settings` `live.budgetNote`: what the author pays for the live agents, as the demo's build sets it (CONTRACTS 9,
 * v1.37). Absent: the banner reads the instance's own cap.
 */
export interface LiveBudgetNote {
  amountUsd: number;
  period: 'day' | 'hour';
}

/** `GET /settings` `heldMessages`: held cases (failure kind `unreadable`) by the schema category they name. */
export interface HeldMessages {
  count: number;
  /** By category and the namespace that lacked it: SHUTTER for Shutter's own feed, HOSPITAL for a watched engine's. */
  categories: { category: string; namespace?: string; count: number; oldest?: string }[];
}

/**
 * `GET /settings` `live` (CONTRACTS 4.4, v1.34), the live hospital's status for the banner: `{enabled: false}` where there
 * is no hospital or player. Times are ISO 8601 UTC. Everything but `enabled` may be missing, as before the first story.
 */
export interface LiveStatus {
  enabled: boolean;
  /** Minutes between two stories. */
  every_minutes?: number;
  /** The scenarios in the rotation, as one comma-separated list. */
  scenarios?: string;
  /** The story played last. */
  last_played?: LivePlay | null;
  /** The story due next, and when. */
  next?: { scenario: string; at: string } | null;
  /** The last ordinary message: its kind and when ("admission at 2026-11-01T10:04:00Z"). */
  last_ordinary?: string;
  /** "Break the feed" (v1.35): the storm playing or played last, absent before the first. */
  storm?: LiveStorm | null;
  /** Whether live agent runs can go out now (v1.37); absent from an older server. */
  agents?: LiveAgents;
  /** What the author pays for the live agents, for the banner; absent until the server sends it. */
  budgetNote?: LiveBudgetNote;
}

/**
 * A storm's state (CONTRACTS 4.4, v1.35): asked for, its movements going out, all sent while the receiver is down, the
 * receiver back and the chains released, then done (the incident closed, or ten minutes after the press) or failed.
 */
export type StormState = 'requested' | 'sending' | 'waiting_receiver' | 'releasing' | 'done' | 'failed';

/** One of the storm's four fresh patients: admitted to `ward`, then moved to `toWard`. No names. */
export interface StormPatient {
  mrn: string;
  encounterId: string;
  ward: string;
  toWard?: string;
  movements?: number;
}

/**
 * `GET /settings` `live.storm`: the player's record of the storm (or the press it has not picked up yet), with
 * Shutter's own view added: the incident its cases joined, how many cases it opened and resolved, and when the next
 * storm may start.
 */
export interface LiveStorm {
  stormId: string;
  state: StormState | string;
  startedAt?: string;
  requestedBy?: string;
  receiverDownUntil?: string;
  receiverUpAt?: string;
  /** Movements sent so far. */
  sent?: number;
  /** Movements in the storm (8). */
  movements?: number;
  /** The patients once the player has planned the storm; the press's own record says only how many (4). */
  patients?: StormPatient[] | number;
  endsAt?: string;
  endedAt?: string;
  /** Set when the storm failed. */
  error?: string;
  incidentId?: string | null;
  incidentState?: string | null;
  cases?: number;
  resolved?: number;
  cooldownUntil?: string;
}

/** `POST /live/storm`'s 202: the press as recorded, before the player takes it. */
export type StormStarted = LiveStorm & {
  receiverDownSeconds?: number;
  pickupWithinSeconds?: number;
};

/** One story the live hospital played (`^Hospital.Live("played", n)`). */
export interface LivePlay {
  scenario: string;
  title: string;
  at: string;
  n?: number;
  /** Who it played for: MRN, given name and family name of each synthetic patient. */
  patients?: string[];
  messages?: number;
  /** Set when the story or one of its faults failed. */
  error?: string;
}

export interface Costs {
  /**
   * What was spent: live and record runs. A replay reuses a recording's tokens and costs nothing, and so does a run the
   * API mimic answered (model mock, a test fixture), counted in mockRuns and not in liveRuns.
   */
  totals?: {
    spentUsd: number;
    liveRuns: number;
    replayedRuns: number;
    mockRuns?: number;
    /** Production reviews whose agent answered, in any mode (CONTRACTS 13); spentUsd includes their live runs. */
    reviewRuns?: number;
    /** The runs that answered a question about a case (CONTRACTS 14.2), counted in the rows above too. */
    questionRuns?: number;
  };
  byModel: {
    model: string;
    /** live, record or replay: replays have their own rows, at no cost. */
    mode?: string;
    runs: number;
    promptTokens: number;
    completionTokens: number;
    cacheReadTokens: number;
    costUsd: number;
  }[];
  byDay: { day: string; runs: number; replayedRuns?: number; costUsd: number }[];
  byCase: { caseId: string; runs: number; replayedRuns?: number; costUsd: number }[];
  /** The production reviews' agent runs, apart from the board's: a replay or a mimic run costs nothing. */
  byReview?: {
    reviewId: string;
    production: string;
    model: string;
    mode: string;
    costUsd: number;
    startedAt: string;
  }[];
  /** The questions' agent runs by question (CONTRACTS 14.2): a replay costs nothing. */
  byQuestion?: { questionId: string; caseId: string; runs: number; replayedRuns?: number; costUsd: number }[];
}

// ---- the production review (CONTRACTS 13) ----

/** A production a review may read: Shutter's own, or a watched one its cases came from. */
export interface ReviewTarget {
  namespace: string;
  production: string;
  productionState: string;
  own: boolean;
  watched: boolean;
}

export type ReviewState = 'sweeping' | 'ranking' | 'done' | 'failed';
export type ReviewAgentState = 'pending' | 'ok' | 'no_record' | 'skipped' | 'schema_failed' | 'error';
export type Severity = 'high' | 'medium' | 'low' | 'info';
export type ReviewConfidence = 'confirmed' | 'consistent' | 'indicative';
export type FindingSource = 'item' | 'default_setting' | 'class_default' | 'observed';
export type FindingStatus = 'new' | 'intended' | 'accepted_risk' | 'false_positive';

/** The review's counts; {} while it is still sweeping. */
export interface ReviewSummary {
  bySeverity?: Record<Severity, number>;
  findings?: number;
  /** Findings with a status other than new, as the annotations stand now. */
  intended?: number;
  items?: number;
  errorsInWindow?: number;
  messageErrorsInWindow?: number;
  /** HL7 operations (the reply code checks' subject), when the server counts them; absent from older reviews. */
  hl7Operations?: number;
  /** HL7 TCP operations and services (the framing check's subject), when the server counts them. */
  hl7TcpItems?: number;
}

export interface ReviewListItem {
  reviewId: string;
  namespace: string;
  production: string;
  productionState: string;
  startedAt: string;
  /** null while the review is sweeping or ranking. */
  finishedAt: string | null;
  state: ReviewState;
  agentState: ReviewAgentState;
  summary: ReviewSummary;
  requestedBy: string;
}

export interface ReviewList {
  items: ReviewListItem[];
  total: number;
}

/** One check's finding (CONTRACTS 13.2). item is "" for a finding about the production or the namespace. */
export interface ReviewFinding {
  id: string;
  code: string;
  severity: Severity;
  confidence: ReviewConfidence;
  item: string;
  itemClass: string;
  setting: string;
  /** Always text: a value, a count, a signature, or a "; " separated list of items. */
  found: string;
  source: FindingSource;
  suggested: string;
  why: string;
  action: string;
  cases: { count: number; unique: number; latest: string[] };
  /**
   * latestHeaderId (a message header only) and latestAt are "" when nothing was observed; latestLogId is an event log
   * row and latestRuleLogId a rule log row, when the server sends them; example is the latest error text.
   */
  evidence: {
    count: number;
    latestHeaderId: number | string;
    latestLogId?: number | string;
    latestRuleLogId?: number | string;
    latestAt: string;
    example: string;
  };
  status: FindingStatus;
  annotationId: string;
  /** null until the agent answered, then 1..n within the severity tiers. */
  rank: number | null;
  explanation: string;
}

/** Counts by kind (byFailureKind, byOutcome, byReasonCode, byState) and the newest case ids, per item and "_total". */
export interface CaseAggregate {
  count: number;
  unique: number;
  byFailureKind?: Record<string, number>;
  byOutcome?: Record<string, number>;
  byReasonCode?: Record<string, number>;
  byState?: Record<string, number>;
  latest: string[];
}

/** The agent's part; every field from mode to ensMessageId is null until the agent answered. */
export interface ReviewAgent {
  state: ReviewAgentState;
  mode: string | null;
  model: string | null;
  providerConfig: string | null;
  costUsd: number | null;
  promptTokens: number | null;
  completionTokens: number | null;
  cacheReadTokens: number | null;
  cacheCreationTokens: number | null;
  durationMs: number | null;
  recordKey: string | null;
  ensMessageId: string | null;
  error: string;
  summary: string;
  unknowns: string[];
  /**
   * Once the agent answered: the current findings its ranking explained, those it did not (they keep the baseline order
   * within their tier) and the recorded entries no current finding matched (by code, item and setting).
   */
  explained?: number | null;
  unexplained?: number | null;
  dropped?: number | null;
  recordedEntries?: number | null;
}

export interface ReviewDetail extends ReviewListItem {
  /** The sweep's failure text, "" otherwise. */
  error: string;
  window: { days: number; from: string; to: string };
  /** "" when there is no configuration finding. */
  fingerprint: string;
  unreadable: boolean;
  /** In baseline order (severity tier, unique cases, recency); [] while sweeping. */
  findings: ReviewFinding[];
  caseAggregates: Record<string, CaseAggregate>;
  agent: ReviewAgent;
}

export interface ReviewStarted {
  reviewId: string;
  state: ReviewState;
  requestedBy: string;
}

export interface ReviewAnnotation {
  annotationId: string;
  code: string;
  item: string;
  setting: string;
  valueFingerprint: string;
  status: Exclude<FindingStatus, 'new'>;
  reason: string;
  owner: string;
  expiresAt: string | null;
  createdAt: string;
}

/** The readiness report (Shutter.Setup.Doctor); a user without the operator role gets only a few of its keys. */
export type Health = Record<string, unknown> & {
  /** False on a site install: no demo, and the Scenario Player is switched off (CONTRACTS 12). */
  demo?: boolean;
};

// ---- asking about a case (CONTRACTS 14: the deterministic card, the questions and their routes) ----

/** The two tiers: one agent in plain words, or the three specialists and the coordinator. */
export type QuestionTier = 'explain' | 'board';

/** A suggested question's place in its scenario's file: the conversation and its 1-based turn. */
export interface QuestionRef {
  conversation: string;
  turn: number;
}

export type QuestionState = 'pending' | 'answering' | 'answered' | 'schema_failed' | 'failed';

/** One turn of a suggested conversation, as knowledge/questions/<S>.json writes it, with the question asked for it. */
export interface SuggestedTurn {
  turn: number;
  tier: QuestionTier;
  text: string;
  /** The newest question asked for this turn and its state, or null when none has been. */
  asked: { questionId: string; state: QuestionState } | null;
}

/** GET /cases/{id}/questions/suggested; `conversations` is empty for a case with no scenario or no file (not a 404). */
export interface SuggestedQuestions {
  scenario: string;
  conversations: { id: string; turns: SuggestedTurn[] }[];
}

/** A change to one profile field, validated by the server against a copy of the profile (14.1). */
export interface SuggestedProfileChange {
  field: string;
  receiver?: string;
  from: string | boolean | null;
  to: string | boolean;
  why: string;
  affects: string[];
  /** False when the validator refuses the change: no draft is offered, and `problem` says why. */
  valid: boolean;
  problem?: string;
  /** True when `from` no longer matches the profile: no draft is offered. */
  stale: boolean;
}

/**
 * One fact Shutter.Util.WhatIf computes from the case's snapshot: a setting of the site profile its outcome turns on,
 * the value that would change it, and what the case would have done then. The only settings an agent may name.
 */
export interface WhatIfFact {
  /** W1, W2...: what an answer cites. */
  id: string;
  /** alternative: a catalogue alternative's `when`; policy: the tier's approval policy, or a receiver's cancels or merges. */
  kind: 'alternative' | 'policy' | string;
  /** setting: the setting behind the outcome (its change undoes it); alternative: what would make the alternative apply. */
  role: 'setting' | 'alternative' | 'policy' | string;
  flag: string;
  /** The profile field: authoritative_source, receivers[].history_policy, policy.2.single... */
  field: string;
  /** For a receivers[] field: the receiver's name. */
  receiver?: string;
  current: string | boolean | null;
  from: string | boolean | null;
  to: string | boolean;
  /** Whether the alternative's condition holds now. */
  holds_now: boolean;
  /** What the case would have done under the other value, in a sentence. */
  would: string;
  alternative?: { n: number; outcome: string; disposition?: string; when?: string; why?: string };
  /** The kinds of case the change would reach. */
  affects: string[];
  suggested_change: SuggestedProfileChange;
}

/** GET /cases/{id}/whatif: the deterministic card, no model; 404 not_found only for an unknown case. */
export interface WhatIf {
  case_id: string;
  receiver: string;
  category: string;
  /** The matched catalogue entry, and the outcome and disposition the case has now. */
  entry: string;
  outcome: string;
  outcome_ref: string;
  disposition: string;
  /** The site profile version the facts were computed against. */
  profile_version: number;
  note: string;
  facts: WhatIfFact[];
}

/** Shutter.Schema.Answer: what the Explain agent, and each board member, submits. */
export interface Answer {
  answer: string;
  /** Evidence ids of the model view, or W<n> fact ids. */
  cites: string[];
  confidence: 'high' | 'medium' | 'low' | string;
}

/** Shutter.Schema.BoardAnswer: the coordinator's synthesis; the fact references are W ids, never values. */
export interface BoardAnswer extends Answer {
  perspectives: { member: string; view: string }[];
  setting?: { fact: string; why?: string };
  under_alternative?: { fact: string; why?: string };
  suggested_change?: { fact: string; why?: string };
}

/** A question's agent run, as GET /cases/{id}/questions/{qid} lists it. */
export interface QuestionAgentRun {
  runId: string;
  role: string;
  member: string;
  status: string;
  mode: 'live' | 'record' | 'replay' | string | null;
  model: string | null;
  costUsd: number | null;
  durationMs: number | null;
  ensMessageId: string | null;
  error: string | null;
}

/** GET /cases/{id}/questions: one turn of a conversation and its answer (14.5). */
export interface CaseQuestion {
  questionId: string;
  caseId: string;
  conversation: string;
  turn: number;
  tier: QuestionTier;
  /** suggested: a turn of the scenario's file, recorded and replayable; free: live only. */
  source: 'suggested' | 'free';
  question: string;
  state: QuestionState;
  askedBy: string;
  askedAt: string;
  /** Null until set. */
  answeredAt: string | null;
  /** Why the answer was refused (schema_failed) or the run failed. */
  error: string | null;
  /** `replay` marks a recorded answer. */
  mode: 'live' | 'record' | 'replay' | string | null;
  model: string | null;
  costUsd: number | null;
  runs: number;
  recordKey: string | null;
  ensMessageId: string | null;
  /** The accepted answer, null until answered. */
  answer: Answer | BoardAnswer | null;
  /**
   * When a replayed answer was recorded live. The server does not send this yet: the provenance label reads it if it
   * is present and otherwise answeredAt.
   */
  recordedAt?: string | null;
}

/** GET /cases/{id}/questions: oldest first. */
export interface CaseQuestions {
  items: CaseQuestion[];
  total: number;
}

/** GET /cases/{id}/questions/{qid}: the list's fields and what the answer was made from. */
export interface CaseQuestionDetail extends CaseQuestion {
  /** The what-if facts as handed to the agents. */
  facts: WhatIfFact[];
  memberAnswers: { member: string; status: string; answer?: Answer; error?: string }[];
  /** What the core resolved from its own facts (14.4), never from the agent's text. */
  resolved: {
    setting?: WhatIfFact;
    under_alternative?: WhatIfFact;
    suggested_change?: SuggestedProfileChange;
  };
  agentRuns: QuestionAgentRun[];
}

/** POST /cases/{id}/questions: a fresh question, or a suggested turn, in a conversation (a new one when none is named). */
export type AskQuestion = { tier: QuestionTier; conversation?: string } & (
  { question: string; suggested?: never } | { suggested: QuestionRef; question?: never }
);

/** POST /cases/{id}/questions answers 202 with where the question sits. */
export interface QuestionAsked {
  questionId: string;
  conversation: string;
  turn: number;
  tier: QuestionTier;
  source: 'suggested' | 'free';
  state: QuestionState;
  askedBy: string;
}
