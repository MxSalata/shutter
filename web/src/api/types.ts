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

export type Disposition = 'resend' | 'reconcile' | 'superseded' | 'more_evidence' | 'escalate';

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
  /** The incident that holds the case, when one does (CONTRACTS 7.5). */
  incidentId?: string;
}

export interface CaseList {
  items: CaseSummary[];
  total: number;
}

export interface CaseDetail extends CaseSummary {
  operationKey: string;
  /** No catalogue entry fitted the case: it is flagged as a candidate for a new entry (CONTRACTS 6.3). */
  candidateEntry?: boolean;
  failureKind: string;
  failureText: string;
  patientId: string;
  patientIdAuthority: string;
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
  planDigest: string;
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
  outcome: 'verified' | 'unresolved' | 'failed' | string;
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
  reason: string;
  encounterAfter: unknown;
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
}

export interface SiteTeam {
  id: string;
  name: string;
  mailbox: string;
  cc?: string[];
  /** The receivers (production items) whose cases this team corrects. */
  receivers?: string[];
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
  policy: Record<string, Partial<Record<ChainKind, string>>>;
  approvers?: { role?: string; escalation?: string; [key: string]: unknown };
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
}

export interface Costs {
  /** What was spent: live and record runs. A replay reuses a recording's tokens and costs nothing. */
  totals?: { spentUsd: number; liveRuns: number; replayedRuns: number };
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
}

export type Health = Record<string, unknown>;
