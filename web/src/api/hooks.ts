import { useMutation, useQueries, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, newIdempotencyKey, seg } from './client';
import { resolveCan } from './can';
import { isApiError } from '@/lib/errors';
import {
  CLOSED_STATES,
  type AccessReport,
  type ApprovalDecision,
  type ApprovalsView,
  type AttemptView,
  type BlindResendPreview,
  type BlockedReason,
  type RecoveryControl,
  type CaseDetail,
  type CaseEvent,
  type CaseList,
  type CaseState,
  type Closure,
  type Costs,
  type Health,
  type Escalation,
  type IncidentDecision,
  type IncidentDetail,
  type IncidentEvent,
  type IncidentList,
  type LiveStatus,
  type LibraryMember,
  type Me,
  type Mode,
  type PlanView,
  type Precedent,
  type PrecedentsView,
  type ReviewAnnotation,
  type ReviewDetail,
  type ReviewList,
  type ReviewStarted,
  type ReviewState,
  type ReviewTarget,
  type RunStarted,
  type AgentRun,
  type AskPageQuestion,
  type AskQuestion,
  type CaseQuestionDetail,
  type CaseQuestions,
  type PageQuestion,
  type PageQuestionAsked,
  type QuestionAsked,
  type QuestionState,
  type SuggestedQuestions,
  type WhatIf,
  type Scenario,
  type ScenarioList,
  type ScenarioRun,
  type Settings,
  type SiteProfile,
  type SiteProfileVersionEntry,
  type SiteProfileView,
  type Snapshot,
  type StormStarted,
} from './types';
import { isStormPlaying, LIVE_POLL_MS, STORM_POLL_MS } from '@/lib/storm';

/** How often an open case and the lists refresh, in milliseconds. */
const LIVE = 2_500;
const CALM = 15_000;

export const keys = {
  me: ['me'] as const,
  scenarios: ['scenarios'] as const,
  cases: (filters: CaseFilters) => ['cases', filters] as const,
  case: (id: string) => ['case', id] as const,
  part: (id: string, part: string) => ['case', id, part] as const,
  incidents: (filters: IncidentFilters) => ['incidents', filters] as const,
  incident: (id: string) => ['incident', id] as const,
  incidentEvents: (id: string) => ['incident', id, 'events'] as const,
  escalations: (id: string) => ['case', id, 'escalations'] as const,
  recoveryControl: ['recovery-control'] as const,
  siteProfile: ['site-profile'] as const,
  siteProfileHistory: ['site-profile', 'history'] as const,
  library: ['library'] as const,
  settings: ['settings'] as const,
  access: ['access'] as const,
  costs: ['costs'] as const,
  health: ['health'] as const,
  reviewTargets: ['production-reviews', 'targets'] as const,
  reviews: (filters: ReviewFilters) => ['production-reviews', filters] as const,
  review: (id: string) => ['production-review', id] as const,
  questions: (id: string) => ['case', id, 'questions'] as const,
  question: (id: string, qid: string) => ['case', id, 'questions', qid] as const,
  suggested: (id: string) => ['case', id, 'suggested-questions'] as const,
  pageQuestion: (qid: string) => ['page-question', qid] as const,
  whatif: (id: string) => ['case', id, 'whatif'] as const,
};

// ---- the session (5.1) ----

/** The signed-in user, or null when the API says nobody is (401). */
export function useMe() {
  return useQuery({
    queryKey: keys.me,
    queryFn: async () => {
      try {
        return await api.get<Me>('/me');
      } catch (e) {
        if (isApiError(e) && e.isUnauthorized) return null;
        throw e;
      }
    },
    staleTime: 60_000,
    retry: false,
  });
}

/** What the signed-in user may do: the server's `can`, or what the operator and approver flags give (api/can.ts). */
export function useCan() {
  return resolveCan(useMe().data);
}

export function useSignIn() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (credentials: { username: string; password: string }) =>
      api.post<unknown>('/session', credentials),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: keys.me });
    },
  });
}

/** The window event a sign-out sends, for the parts of the page that keep state of their own (the guide). */
export const SIGNED_OUT = 'shutter:signed-out';

export function useSignOut() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.del<unknown>('/session'),
    // Whatever the server answered, this browser forgets everything it showed. The guide (trial pages only) hears
    // SIGNED_OUT, closes and drops its copy in memory; the place stored on the device stays, like the appearance.
    onSettled: () => {
      window.dispatchEvent(new Event(SIGNED_OUT));
      client.clear();
      client.setQueryData(keys.me, null);
    },
  });
}

// ---- scenarios (5.2) ----

/** A run that is queued for the scenario player or playing. */
export function isPlaying(run: ScenarioRun | null | undefined): boolean {
  return run?.state === 'running' || run?.state === 'queued';
}

/** A case in these states is waiting on a person or an incident, or is closed; in any other it is working now. */
const AT_REST: readonly CaseState[] = [...CLOSED_STATES, 'awaiting_approval', 'grouped'];

/**
 * The case a finished run left still working, if any. A new run resets the demo receiver under it, so it would end as
 * Abandoned and its later approval would be blocked with UNKNOWN_ENCOUNTER: Run waits for it.
 */
export function settlingCase(list: ScenarioList | null | undefined): Scenario['latestCase'] {
  if (list?.run?.state !== 'done') return null;
  const latest = list.scenarios.find((s) => s.id === list.run?.scenario)?.latestCase ?? null;
  return latest && !AT_REST.includes(latest.state) ? latest : null;
}

/** The scenarios and, when the API reports it, the current or last background run (T13). */
export function useScenarios() {
  return useQuery({
    queryKey: keys.scenarios,
    queryFn: async (): Promise<ScenarioList> => {
      const data = await api.get<Scenario[] | ScenarioList>('/scenarios');
      return Array.isArray(data)
        ? { scenarios: data, run: null }
        : { scenarios: data.scenarios ?? [], run: data.run ?? null };
    },
    refetchInterval: (query) =>
      isPlaying(query.state.data?.run) || settlingCase(query.state.data) ? 2_000 : CALM,
  });
}

export function useRunScenario() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, mode }: { id: string; mode: Mode }) =>
      api.post<RunStarted>(`/scenarios/${seg(id)}/run`, { mode }, { idempotencyKey: newIdempotencyKey() }),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: keys.scenarios });
      await client.invalidateQueries({ queryKey: ['cases'] });
      await client.invalidateQueries({ queryKey: ['incidents'] });
    },
  });
}

export function useResetScenarios() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.post<{ reset: boolean; resetAt: string }>('/scenarios/reset'),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: keys.scenarios });
      await client.invalidateQueries({ queryKey: ['cases'] });
      await client.invalidateQueries({ queryKey: ['incidents'] });
    },
  });
}

// ---- cases (5.3) ----

export interface CaseFilters {
  state?: string;
  scenario?: string;
  /**
   * 1 leaves out the closed cases (CLOSED_STATES: resolved, blocked, escalated, failed). The server filters and counts
   * them, so `total` and every page are of the open cases only (CONTRACTS 5).
   */
  open?: 1;
  limit?: number;
  offset?: number;
}

/** The cases list; `enabled` false leaves it unread, for a panel that needs it only for some cases. */
export function useCases(filters: CaseFilters, enabled = true) {
  return useQuery({
    ...casesQuery(filters),
    refetchInterval: (q) => (q.state.data?.items.some((c) => isOpen(c.state)) ? LIVE * 2 : CALM),
    enabled,
  });
}

/** How many of the newest failed cases the count below reads, to take the abandoned ones off. */
export const FAILED_READ = 100;

export interface FailedForAPerson {
  /** The failed cases that need a person, as far as the read can tell. */
  count: number;
  /**
   * True when more cases failed than were read: one a person gave up among the older ones is still counted, so the
   * figure is an upper bound and is shown as one ("at most").
   */
  atMost: boolean;
}

/**
 * How many failed cases need a person, undefined while it loads: a case a person gave up is failed too, and is counted
 * under By hand. The API counts by state only, so the abandoned ones are taken off among the newest 100; with more
 * failed cases than that the older ones were not read, and the count says it is an upper bound (`atMost`), which errs
 * towards a person looking.
 */
export function useFailedCount(): FailedForAPerson | undefined {
  const { data } = useCases({ state: 'failed', limit: FAILED_READ });
  if (!data) return undefined;
  return {
    count: data.total - data.items.filter((c) => c.disposition === 'abandoned').length,
    atMost: data.total > data.items.length,
  };
}

/** The count alone, for a sum of what needs a person (the navigation, Home): an upper bound past 100 failed cases. */
export function useFailedForAPerson(): number | undefined {
  return useFailedCount()?.count;
}

/**
 * The cases list read once, not polled: for a link that only needs one case's id. These sit on every page or on Home for
 * every visitor of the public instance, where polling them would add a request every few seconds to name the same case.
 * Once means once: never stale, so a remount or a second reader of the same list asks nothing more. A decision on a
 * held case marks every cases list stale, so Home's link to a held plan is read again when Home is next shown.
 */
export function useCasesOnce(filters: CaseFilters, enabled = true) {
  return useQuery({ ...casesQuery(filters), enabled, staleTime: Infinity });
}

function casesQuery(filters: CaseFilters) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== '') params.set(k, String(v));
  const query = params.toString();
  return {
    queryKey: keys.cases(filters),
    queryFn: () => api.get<CaseList>(`/cases${query ? `?${query}` : ''}`),
  };
}

export function isOpen(state: CaseState | string | undefined): boolean {
  return !!state && !CLOSED_STATES.includes(state as CaseState);
}

export function useCase(caseId: string, enabled = true) {
  return useQuery({
    queryKey: keys.case(caseId),
    queryFn: () => api.get<CaseDetail>(`/cases/${seg(caseId)}`),
    refetchInterval: (q) => (isOpen(q.state.data?.state) ? LIVE : false),
    enabled,
  });
}

/** Several cases, each read once, for a dialog that names what it covers. */
export function useCaseDetails(caseIds: string[]) {
  return useQueries({
    queries: caseIds.map((caseId) => ({
      queryKey: keys.case(caseId),
      queryFn: () => api.get<CaseDetail>(`/cases/${seg(caseId)}`),
    })),
  });
}

/**
 * A part of a case (events, snapshot, runs, plan...). It refreshes while the case is open; a 404 (no plan yet, no
 * closure yet) is an answer, shown as "not yet", so it reads as null rather than an error. `notYet` says the case is too
 * young to have this part: the answer is the same null, with no request, so the browser's console logs no 404.
 */
export function useCasePart<T>(
  caseId: string,
  part: string,
  path: string,
  open: boolean,
  enabled = true,
  notYet = false,
) {
  return useQuery({
    queryKey: keys.part(caseId, part),
    queryFn: async (): Promise<T | null> => {
      if (notYet) return null;
      try {
        return await api.get<T>(`/cases/${seg(caseId)}${path}`);
      } catch (e) {
        if (isApiError(e) && e.isNotFound) return null;
        throw e;
      }
    },
    enabled,
    refetchInterval: open ? LIVE : false,
  });
}

export const useCaseEvents = (id: string, open: boolean) =>
  useCasePart<CaseEvent[]>(id, 'events', '/events', open);
/** A case in this state has no evidence snapshot or plan yet, and it is in this state only once, at its start. */
export const beforeEvidence = (state: string | undefined) => state === 'detected';
export const useSnapshot = (id: string, open: boolean, notYet = false) =>
  useCasePart<Snapshot>(id, 'snapshot', '/snapshot', open, true, notYet);
export const useRuns = (id: string, open: boolean) => useCasePart<AgentRun[]>(id, 'runs', '/runs', open);
export const usePlan = (id: string, open: boolean, notYet = false) =>
  useCasePart<PlanView>(id, 'plan', '/plan', open, true, notYet);
export const useApprovals = (id: string, open: boolean) =>
  useCasePart<ApprovalsView>(id, 'approvals', '/approvals', open);
export const useAttempts = (id: string, open: boolean) =>
  useCasePart<AttemptView[]>(id, 'attempts', '/attempts', open);
export const useClosure = (id: string, closed: boolean) =>
  useCasePart<Closure>(id, 'closure', '/closure', false, closed);
/**
 * The precedents the case's conditions match at its receiver (CONTRACTS 6.4, v1.35), read when asked for: the summary
 * as it stands now, and every row, retired ones included. A server older than the route answers 404, read as null.
 */
export const usePrecedents = (id: string, enabled: boolean) =>
  useCasePart<PrecedentsView>(id, 'precedents', '/precedents', false, enabled);

/**
 * Retire a precedent (approver only): it stays on record and counts for nothing. 409 already_retired names who
 * retired it and when, in its detail. The list and the summary are read again either way.
 */
export function useRetirePrecedent(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, reason }: { id: string | number; reason: string }) =>
      api.post<Precedent>(`/precedents/${seg(String(id))}/retire`, { reason }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.part(caseId, 'precedents') });
    },
  });
}
/**
 * The blocked reason: the catalogue entry and the gate's failing checks. The API nests the entry
 * (`{code, catalogue, failingChecks}`); the flat shape of CONTRACTS 5.3 is read too.
 */
export function useBlockedReason(caseId: string, enabled: boolean) {
  return useQuery({
    queryKey: keys.part(caseId, 'blocked-reason'),
    enabled,
    queryFn: async (): Promise<BlockedReason | null> => {
      try {
        const raw = await api.get<Record<string, unknown>>(`/cases/${seg(caseId)}/blocked-reason`);
        const entry = (raw.catalogue && typeof raw.catalogue === 'object' ? raw.catalogue : raw) as Record<
          string,
          unknown
        >;
        const text = (k: string) => (typeof entry[k] === 'string' ? (entry[k] as string) : '');
        return {
          code: (typeof raw.code === 'string' && raw.code) || text('code'),
          title: text('title'),
          prerequisite: text('prerequisite'),
          nextAction: text('nextAction'),
          owner: text('owner'),
          reevaluateWhen: text('reevaluateWhen'),
          text: text('text'),
          checks: (Array.isArray(raw.failingChecks)
            ? raw.failingChecks
            : Array.isArray(raw.checks)
              ? raw.checks
              : []) as BlockedReason['checks'],
        };
      } catch (e) {
        if (isApiError(e) && e.isNotFound) return null;
        throw e;
      }
    },
  });
}

export function useDecideApproval(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ decision, idempotencyKey }: { decision: ApprovalDecision; idempotencyKey: string }) =>
      api.post<{ taskId: string; decision: string; caseId: string; approver: string }>(
        `/cases/${seg(caseId)}/approvals`,
        decision,
        {
          idempotencyKey,
        },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
      // The lists read once still name the case as held: stale now, read again by the next page that shows them
      await client.invalidateQueries({ queryKey: ['cases'], refetchType: 'none' });
    },
  });
}

/** Reopen a blocked, escalated or failed case: fresh evidence and a new plan version (CONTRACTS 5.3, A3). */
export function useReinvestigate(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ reason, idempotencyKey }: { reason: string; idempotencyKey: string }) =>
      api.post<{ caseId: string; state: string }>(
        `/cases/${seg(caseId)}/reinvestigate`,
        { reason },
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
    },
  });
}

/**
 * Convene the board on a case, live (CONTRACTS 5.3, v1.34): the case is investigated again on fresh evidence and the
 * board decides whatever the site's policy says. Needs Shutter_LiveAgents; 409 budget_exhausted when the day's budget, or
 * the caller's share of it, is spent.
 */
export function useConveneBoard(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ idempotencyKey }: { idempotencyKey: string }) =>
      api.post<{ caseId: string; state: string; requestedBy?: string }>(
        `/cases/${seg(caseId)}/board`,
        {},
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
      await client.invalidateQueries({ queryKey: keys.settings });
    },
  });
}

/**
 * Close a case the team corrected by hand (a withheld merge or cancel, an escalation acted on): it resolves as
 * handled_by_hand and a draft or queued email is cancelled (CONTRACTS 5.3, v1.14).
 */
export function useCloseCase(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      reason,
      expectedVersion,
      idempotencyKey,
    }: {
      reason: string;
      expectedVersion?: number;
      idempotencyKey: string;
    }) =>
      api.post<{ caseId: string; state: string; requestedBy: string; reason: string }>(
        `/cases/${seg(caseId)}/close`,
        { reason, ...(expectedVersion !== undefined ? { expectedVersion } : {}) },
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
      await client.invalidateQueries({ queryKey: keys.escalations(caseId) });
    },
  });
}

/**
 * Abandon a case its workflow left in a working state (CONTRACTS 5): approver only, refused with 409 busy while the
 * workflow has a message in flight. The case then fails with disposition abandoned and can be reinvestigated.
 */
export function useAbandonCase(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      reason,
      expectedVersion,
      idempotencyKey,
    }: {
      reason: string;
      expectedVersion: number;
      idempotencyKey: string;
    }) =>
      api.post<{ caseId: string; state: string; requestedBy: string; reason: string }>(
        `/cases/${seg(caseId)}/abandon`,
        { reason, expectedVersion },
        { idempotencyKey },
      ),
    onSettled: async () => {
      // The case's key is the prefix of its parts (events, closure, approvals), so they refetch too.
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
      await client.invalidateQueries({ queryKey: keys.escalations(caseId) });
    },
  });
}

export function usePreviewBlindResend(caseId: string) {
  return useMutation({
    mutationFn: () => api.post<BlindResendPreview>(`/cases/${seg(caseId)}/preview-blind-resend`),
  });
}

// ---- escalations (T29) ----

export function useEscalations(caseId: string, enabled: boolean) {
  return useQuery({
    queryKey: keys.escalations(caseId),
    enabled,
    queryFn: () => api.get<Escalation[]>(`/cases/${seg(caseId)}/escalations`),
    // A queued email is sent by the production a moment later: look again until it has gone
    refetchInterval: (q) => (q.state.data?.some((e) => e.state === 'queued') ? 2_000 : false),
  });
}

/** A new draft, built by Shutter from the case for a team of the site profile (the receiver's when none is named). */
export function useDraftEscalation(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ teamId, idempotencyKey }: { teamId?: string; idempotencyKey: string }) =>
      api.post<Escalation>(`/cases/${seg(caseId)}/escalations`, teamId ? { teamId } : {}, { idempotencyKey }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.escalations(caseId) });
    },
  });
}

export function useEditEscalation(caseId: string) {
  return useMutation({
    mutationFn: ({
      seq,
      change,
    }: {
      seq: number;
      change: Pick<Escalation, 'subject' | 'body' | 'to' | 'cc'>;
    }) => api.patch<Escalation>(`/cases/${seg(caseId)}/escalations/${seq}`, change),
  });
}

/** Sends the draft the person read: the digest binds it, as an approval binds a plan. */
export function useSendEscalation(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      seq,
      bodyDigest,
      idempotencyKey,
    }: {
      seq: number;
      bodyDigest: string;
      idempotencyKey: string;
    }) =>
      api.post<Escalation>(
        `/cases/${seg(caseId)}/escalations/${seq}/send`,
        { bodyDigest },
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.escalations(caseId) });
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
    },
  });
}

// ---- incidents (CONTRACTS 7.5) ----

export interface IncidentFilters {
  state?: string;
  limit?: number;
}

/** The incidents list; `enabled` false asks nothing (the live banner asks only on the live hospital). */
export function useIncidents(filters: IncidentFilters, enabled = true) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== '') params.set(k, String(v));
  const query = params.toString();
  return useQuery({
    queryKey: keys.incidents(filters),
    queryFn: () => api.get<IncidentList>(`/incidents${query ? `?${query}` : ''}`),
    enabled,
    refetchInterval: (q) => (q.state.data?.items.some((i) => i.state !== 'closed') ? LIVE * 2 : CALM),
  });
}

export function useIncident(incidentId: string) {
  return useQuery({
    queryKey: keys.incident(incidentId),
    queryFn: () => api.get<IncidentDetail>(`/incidents/${seg(incidentId)}`),
    refetchInterval: (q) => (q.state.data && q.state.data.state !== 'closed' ? LIVE : false),
  });
}

export function useIncidentEvents(incidentId: string, open: boolean) {
  return useQuery({
    queryKey: keys.incidentEvents(incidentId),
    queryFn: () => api.get<IncidentEvent[]>(`/incidents/${seg(incidentId)}/events`),
    refetchInterval: open ? LIVE : false,
  });
}

/** Approve or reject the incident's policy chains, or with chainSeq one chain released under its own approval. */
export function useDecideIncident(incidentId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      decision,
      chainSeq,
      idempotencyKey,
    }: {
      decision: IncidentDecision;
      chainSeq?: number;
      idempotencyKey: string;
    }) =>
      api.post<{ taskId: string; decision: string; incidentId: string; chainSeq?: number; approver: string }>(
        chainSeq === undefined
          ? `/incidents/${seg(incidentId)}/approvals`
          : `/incidents/${seg(incidentId)}/chains/${chainSeq}/approvals`,
        decision,
        { idempotencyKey },
      ),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.incident(incidentId) });
      await client.invalidateQueries({ queryKey: ['incidents'] });
    },
  });
}

// ---- the recovery control (CONTRACTS 18) ----

export function useRecoveryControl() {
  return useQuery({
    queryKey: keys.recoveryControl,
    queryFn: () => api.get<RecoveryControl>('/recovery-control'),
    refetchInterval: 15_000,
    retry: false,
  });
}

// ---- the site profile (CONTRACTS 6.4) ----

export function useSiteProfile() {
  return useQuery({ queryKey: keys.siteProfile, queryFn: () => api.get<SiteProfileView>('/site-profile') });
}

export function useSiteProfileHistory() {
  return useQuery({
    queryKey: keys.siteProfileHistory,
    queryFn: () => api.get<SiteProfileVersionEntry[]>('/site-profile/history?limit=50'),
  });
}

/** Stores the whole profile; expectedVersion is the version read, so a change saved meanwhile is refused (409). */
export function useSaveSiteProfile() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (body: SiteProfile & { expectedVersion: number }) =>
      api.put<SiteProfileView>('/site-profile', body),
    onSuccess: (data) => {
      client.setQueryData(keys.siteProfile, data);
    },
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.siteProfileHistory });
    },
  });
}

// ---- library, settings, costs, health (5.4) ----

export function useLibrary() {
  return useQuery({ queryKey: keys.library, queryFn: () => api.get<LibraryMember[]>('/library') });
}

export function usePatchMember() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      code,
      change,
    }: {
      code: string;
      change: Partial<Pick<LibraryMember, 'enabled' | 'inDefaultBoard' | 'sort'>>;
    }) => api.patch<LibraryMember>(`/library/${seg(code)}`, change),
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: keys.library });
    },
  });
}

/** What each of Shutter's roles may do beside what the signed-in user may (`GET /access`): read only, for Settings. */
export function useAccess() {
  return useQuery({ queryKey: keys.access, queryFn: () => api.get<AccessReport>('/access') });
}

export function useSettings() {
  return useQuery({ queryKey: keys.settings, queryFn: () => api.get<Settings>('/settings') });
}

/**
 * How often the live hospital's banner reads the settings again, in milliseconds: every 3 s while a storm plays (the
 * strip follows it), every half minute otherwise while a live hospital is on, and never on any other instance.
 */
export function livePollInterval(settings: Settings | undefined, now: number = Date.now()): number | false {
  if (!settings?.live?.enabled) return false;
  return isStormPlaying(settings.live.storm, now) ? STORM_POLL_MS : LIVE_POLL_MS;
}

/**
 * The live hospital's status (`GET /settings`, `live`), for the banner on every page: null unless the server says
 * `live.enabled`. It reads the settings again only while a live hospital is on (livePollInterval), so no other
 * instance polls for it. A user who may not read the settings (a 403) has no banner.
 */
export function useLiveStatus(): LiveStatus | null {
  const settings = useQuery({
    queryKey: keys.settings,
    queryFn: () => api.get<Settings>('/settings'),
    refetchInterval: (query) => livePollInterval(query.state.data),
  });
  const live = settings.data?.live;
  return live?.enabled === true ? live : null;
}

/**
 * "Break the feed" (CONTRACTS 4.4, v1.35): asks the live hospital for a storm, under the Idempotency-Key of the press
 * (one per press of the button, reused only when that same confirm is sent again after an error, so a lost answer
 * never starts a second storm). The 202 is the press as recorded; it stands in the settings' `live.storm` at once, so
 * the strip appears before the next read, and the settings are read again whatever the answer (a refusal for a storm
 * in progress then shows that one).
 */
export function useStartStorm() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (idempotencyKey: string) => api.post<StormStarted>('/live/storm', {}, { idempotencyKey }),
    onSuccess: (storm) => {
      client.setQueryData<Settings>(keys.settings, (old) =>
        old?.live ? { ...old, live: { ...old.live, storm } } : old,
      );
    },
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.settings });
    },
  });
}

export function useCosts() {
  return useQuery({ queryKey: keys.costs, queryFn: () => api.get<Costs>('/costs') });
}

export function useHealth() {
  return useQuery({ queryKey: keys.health, queryFn: () => api.get<Health>('/health') });
}

// ---- the production review (CONTRACTS 13) ----

export interface ReviewFilters {
  namespace?: string;
  production?: string;
  limit?: number;
}

/** A review the production item is still working on: the sweep, then the agent's ranking. */
export function isReviewRunning(state: ReviewState | string | undefined): boolean {
  return state === 'sweeping' || state === 'ranking';
}

export function useReviewTargets() {
  return useQuery({
    queryKey: keys.reviewTargets,
    queryFn: () => api.get<{ items: ReviewTarget[] }>('/production-reviews/targets'),
    staleTime: 60_000,
  });
}

export function useReviews(filters: ReviewFilters = {}) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== '') params.set(k, String(v));
  const query = params.toString();
  return useQuery({
    queryKey: keys.reviews(filters),
    queryFn: () => api.get<ReviewList>(`/production-reviews${query ? `?${query}` : ''}`),
    refetchInterval: (q) => (q.state.data?.items.some((r) => isReviewRunning(r.state)) ? LIVE * 2 : CALM),
  });
}

/** One review; it is read every 2 s while it sweeps or ranks (the sweep takes seconds, the agent up to 600 s). */
export function useReview(reviewId: string) {
  return useQuery({
    queryKey: keys.review(reviewId),
    queryFn: () => api.get<ReviewDetail>(`/production-reviews/${seg(reviewId)}`),
    refetchInterval: (q) => (isReviewRunning(q.state.data?.state) ? 2_000 : false),
  });
}

/** Starts a review: operators; it reads only, and a live agent run spends model credit as a scenario run does. */
export function useStartReview() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      target,
      idempotencyKey,
    }: {
      target: { namespace: string; production: string; windowDays: number; agent: boolean };
      idempotencyKey: string;
    }) => api.post<ReviewStarted>('/production-reviews', target, { idempotencyKey }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: ['production-reviews'] });
    },
  });
}

/**
 * An annotation is computed when a review is read, so it applies to every review of that production: after a change,
 * every review read here is read again.
 */
async function refreshReviews(client: ReturnType<typeof useQueryClient>) {
  await client.invalidateQueries({ queryKey: ['production-review'] });
  await client.invalidateQueries({ queryKey: ['production-reviews'] });
}

/** Marks a finding intended, an accepted risk or a false positive: approvers; a Shutter record, never a production edit. */
export function useAnnotateFinding(reviewId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({
      annotation,
      idempotencyKey,
    }: {
      annotation: {
        findingId: string;
        status: ReviewAnnotation['status'];
        reason: string;
        expiresAt?: string;
      };
      idempotencyKey: string;
    }) =>
      api.post<ReviewAnnotation>(`/production-reviews/${seg(reviewId)}/annotations`, annotation, {
        idempotencyKey,
      }),
    onSettled: () => refreshReviews(client),
  });
}

/** Revokes an annotation (kept for the record): the finding is new again in every review of the production. */
export function useRemoveAnnotation() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (annotationId: string) =>
      api.del<null>(`/production-reviews/annotations/${seg(annotationId)}`),
    onSettled: () => refreshReviews(client),
  });
}

// ---- asking about a case (the case-chat design; read only: no route writes the case, the receiver or the profile) ----

/** A question still waiting for its answer: the list is read again every 2 s until none is. */
export function isAnswering(state: QuestionState | string | undefined): boolean {
  return state === 'pending' || state === 'answering';
}

/** The deterministic What-if card (GET /cases/{id}/whatif): no model, so it reads the same with no key. */
export function useWhatIf(caseId: string, enabled = true) {
  return useCasePart<WhatIf>(caseId, 'whatif', '/whatif', false, enabled);
}

/** The recorded conversations of the case's scenario; `conversations` is empty when it has none. */
export function useSuggestedQuestions(caseId: string, enabled = true) {
  return useQuery({
    queryKey: keys.suggested(caseId),
    enabled,
    staleTime: 60_000,
    queryFn: () => api.get<SuggestedQuestions>(`/cases/${seg(caseId)}/questions/suggested`),
    // A chip's `asked` follows its question's state, so the list is read again while an answer is awaited
    refetchInterval: (q) =>
      q.state.data?.conversations.some((c) => c.turns.some((t) => t.asked && isAnswering(t.asked.state)))
        ? 2_000
        : false,
  });
}

/** Every question asked about the case, each conversation's turns with their answers. */
export function useCaseQuestions(caseId: string, enabled = true) {
  return useQuery({
    queryKey: keys.questions(caseId),
    enabled,
    queryFn: () => api.get<CaseQuestions>(`/cases/${seg(caseId)}/questions`),
    refetchInterval: (q) => (q.state.data?.items.some((x) => isAnswering(x.state)) ? 2_000 : false),
  });
}

/** One question, read every 2 s until it is answered or refused. */
export function useCaseQuestion(caseId: string, questionId: string) {
  return useQuery({
    queryKey: keys.question(caseId, questionId),
    queryFn: () => api.get<CaseQuestionDetail>(`/cases/${seg(caseId)}/questions/${seg(questionId)}`),
    refetchInterval: (q) => (isAnswering(q.state.data?.state) ? 2_000 : false),
  });
}

/** Asks a question: operators; a replayed suggested turn costs nothing, a live one spends model credit. */
export function useAskQuestion(caseId: string) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ ask, idempotencyKey }: { ask: AskQuestion; idempotencyKey?: string }) =>
      api.post<QuestionAsked>(`/cases/${seg(caseId)}/questions`, ask, {
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.questions(caseId) });
      await client.invalidateQueries({ queryKey: keys.suggested(caseId) });
    },
  });
}

// ---- asking about a page (CONTRACTS 14.6; read only: the one route spends only as a live case question does) ----

/** Asks about the page on the screen: 202 with the question's id, then usePageQuestion reads the answer. */
export function useAskPageQuestion() {
  return useMutation({
    mutationFn: ({ ask, idempotencyKey }: { ask: AskPageQuestion; idempotencyKey?: string }) =>
      api.post<PageQuestionAsked>('/page-questions', ask, {
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      }),
  });
}

/** One question about a page, read every 2 s until it is answered or refused. */
export function usePageQuestion(questionId: string | undefined) {
  return useQuery({
    queryKey: keys.pageQuestion(questionId ?? ''),
    enabled: !!questionId,
    queryFn: () => api.get<PageQuestion>(`/page-questions/${seg(questionId!)}`),
    refetchInterval: (q) => (isAnswering(q.state.data?.state) ? 2_000 : false),
  });
}

export type { ScenarioRun };
