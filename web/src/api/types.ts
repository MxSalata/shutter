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

export interface Me {
  username: string;
  operator: boolean;
  approver: boolean;
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
}

export interface ScenarioExpected {
  disposition: string;
  acceptable?: string[];
  write: boolean;
  final_state: string;
  final_ward: string | null;
  failed_operation_key: string;
  blocked_by?: string;
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
  /** How the delivery failed (delivery_failed, uncertain, unmappable, withheld for a merge or a cancel never sent). */
  failureKind: string;
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
  at: string;
  name: string;
  arguments: unknown;
  durationMs: number;
  ok: boolean;
  resultPreview: string;
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
  /** The scenario catalogue's entry the plan follows, when it names one (E1 to E10). */
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
export interface SiteReceiver {
  name: string;
  system?: string;
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
  history_policy?: string;
  authoritative_source?: string;
  unconditional_resend?: string;
  /** forbidden (the default: every merge goes to the PAS team) or allowed. */
  merges?: string;
  policy: Record<string, Partial<Record<ChainKind, string>>>;
  /** close_needs_approver: closing a case by hand needs an approver (the two-person rule); off when absent. */
  approvers?: { role?: string; escalation?: string; close_needs_approver?: boolean };
  incident?: { threshold?: number; window_minutes?: number; quiet_seconds?: number };
  /** Who corrects the systems by hand when Shutter can't, and where their email goes (T29). */
  teams?: SiteTeam[];
  mail?: { from?: string; allowed_domains?: string[] };
  /** What may leave IRIS for a model beyond tokens and flags (CONTRACTS 9). */
  model_content?: { free_text?: boolean };
  /** The zone of times the feed sends without an offset: an IANA name or a fixed offset (CONTRACTS 6.4). */
  feed?: { time_zone?: string };
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
