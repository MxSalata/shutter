/**
 * The REST API's shapes (docs/CONTRACTS.md, section 5): the store's JSON projections, camelCase. Fields the store
 * keeps as JSON text (a plan, a run's result, the gate's checks) may arrive as text or as JSON; `parseJson` in
 * lib/json.ts reads either.
 */

export type CaseState =
  | 'detected'
  | 'collecting'
  | 'investigating'
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

export type Mode = 'board' | 'single' | 'rules';

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
}

export interface CaseList {
  items: CaseSummary[];
  total: number;
}

export interface CaseDetail extends CaseSummary {
  operationKey: string;
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
  observedAt: string;
  digest: string;
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
  mode?: string;
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
  byModel: {
    model: string;
    runs: number;
    promptTokens: number;
    completionTokens: number;
    cacheReadTokens: number;
    costUsd: number;
  }[];
  byDay: { day: string; runs: number; costUsd: number }[];
  byCase: { caseId: string; runs: number; costUsd: number }[];
}

export type Health = Record<string, unknown>;
