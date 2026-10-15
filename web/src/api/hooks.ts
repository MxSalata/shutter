import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, newIdempotencyKey, seg } from './client';
import { isApiError } from '@/lib/errors';
import {
  CLOSED_STATES,
  type ApprovalDecision,
  type ApprovalsView,
  type AttemptView,
  type BlindResendPreview,
  type BlockedReason,
  type CaseDetail,
  type CaseEvent,
  type CaseList,
  type CaseState,
  type Closure,
  type Costs,
  type Health,
  type LibraryMember,
  type Me,
  type Mode,
  type PlanView,
  type RunStarted,
  type AgentRun,
  type Scenario,
  type ScenarioList,
  type ScenarioRun,
  type Settings,
  type Snapshot,
} from './types';

/** How often an open case and the lists refresh, in milliseconds. */
const LIVE = 2_500;
const CALM = 15_000;

export const keys = {
  me: ['me'] as const,
  scenarios: ['scenarios'] as const,
  cases: (filters: CaseFilters) => ['cases', filters] as const,
  case: (id: string) => ['case', id] as const,
  part: (id: string, part: string) => ['case', id, part] as const,
  library: ['library'] as const,
  settings: ['settings'] as const,
  costs: ['costs'] as const,
  health: ['health'] as const,
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

export function useSignOut() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api.del<unknown>('/session'),
    // Whatever the server answered, this browser forgets everything it showed.
    onSettled: () => {
      client.clear();
      client.setQueryData(keys.me, null);
    },
  });
}

// ---- scenarios (5.2) ----

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
    refetchInterval: (query) => (query.state.data?.run?.state === 'running' ? 2_000 : CALM),
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
    },
  });
}

// ---- cases (5.3) ----

export interface CaseFilters {
  state?: string;
  scenario?: string;
  limit?: number;
  offset?: number;
}

export function useCases(filters: CaseFilters) {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v !== undefined && v !== '') params.set(k, String(v));
  const query = params.toString();
  return useQuery({
    queryKey: keys.cases(filters),
    queryFn: () => api.get<CaseList>(`/cases${query ? `?${query}` : ''}`),
    refetchInterval: (q) => (q.state.data?.items.some((c) => isOpen(c.state)) ? LIVE * 2 : CALM),
  });
}

export function isOpen(state: CaseState | string | undefined): boolean {
  return !!state && !CLOSED_STATES.includes(state as CaseState);
}

export function useCase(caseId: string) {
  return useQuery({
    queryKey: keys.case(caseId),
    queryFn: () => api.get<CaseDetail>(`/cases/${seg(caseId)}`),
    refetchInterval: (q) => (isOpen(q.state.data?.state) ? LIVE : false),
  });
}

/**
 * A part of a case (events, snapshot, runs, plan...). It refreshes while the case is open; a 404 (no plan yet, no
 * closure yet) is an answer, shown as "not yet", so it reads as null rather than an error.
 */
function useCasePart<T>(caseId: string, part: string, path: string, open: boolean, enabled = true) {
  return useQuery({
    queryKey: keys.part(caseId, part),
    queryFn: async (): Promise<T | null> => {
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
export const useSnapshot = (id: string, open: boolean) =>
  useCasePart<Snapshot>(id, 'snapshot', '/snapshot', open);
export const useRuns = (id: string, open: boolean) => useCasePart<AgentRun[]>(id, 'runs', '/runs', open);
export const usePlan = (id: string, open: boolean) => useCasePart<PlanView>(id, 'plan', '/plan', open);
/** "2026-10-15 20:19:13.686" (the Workflow engine's UTC time) as ISO 8601; ISO values pass through. */
export function isoUtc(value: unknown): string {
  if (typeof value !== 'string' || !value) return '';
  return /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(value) ? `${value.replace(' ', 'T')}Z` : value;
}

/** The approvals and the Workflow tasks; a task's fields are read in camelCase or snake_case. */
export function useApprovals(caseId: string, open: boolean) {
  return useQuery({
    queryKey: keys.part(caseId, 'approvals'),
    refetchInterval: open ? LIVE : false,
    queryFn: async (): Promise<ApprovalsView | null> => {
      try {
        const raw = await api.get<{
          approvals?: ApprovalsView['approvals'];
          tasks?: Record<string, unknown>[];
        }>(`/cases/${seg(caseId)}/approvals`);
        const pick = (t: Record<string, unknown>, camel: string, snake: string) => t[camel] ?? t[snake];
        const tasks = (raw.tasks ?? []).map((t) => ({
          taskId: String(pick(t, 'taskId', 'task_id') ?? ''),
          subject: String(t.subject ?? ''),
          actions: String(t.actions ?? ''),
          action: String(t.action ?? ''),
          userName: String(pick(t, 'userName', 'user_name') ?? ''),
          role: String(t.role ?? ''),
          complete: Boolean(t.complete),
          assignedTo: String(pick(t, 'assignedTo', 'assigned_to') ?? ''),
          timeCreated: isoUtc(pick(t, 'timeCreated', 'time_created')),
          timeCompleted: isoUtc(pick(t, 'timeCompleted', 'time_completed')),
          planDigest: String(pick(t, 'planDigest', 'plan_digest') ?? ''),
        }));
        return { approvals: raw.approvals ?? [], tasks };
      } catch (e) {
        if (isApiError(e) && e.isNotFound) return null;
        throw e;
      }
    },
  });
}
export const useAttempts = (id: string, open: boolean) =>
  useCasePart<AttemptView[]>(id, 'attempts', '/attempts', open);
export const useClosure = (id: string, closed: boolean) =>
  useCasePart<Closure>(id, 'closure', '/closure', false, closed);
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
      api.post<{ taskId: string; decision: string }>(`/cases/${seg(caseId)}/approvals`, decision, {
        idempotencyKey,
      }),
    onSettled: async () => {
      await client.invalidateQueries({ queryKey: keys.case(caseId) });
    },
  });
}

export function usePreviewBlindResend(caseId: string) {
  return useMutation({
    mutationFn: () => api.post<BlindResendPreview>(`/cases/${seg(caseId)}/preview-blind-resend`),
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

export function useSettings() {
  return useQuery({ queryKey: keys.settings, queryFn: () => api.get<Settings>('/settings') });
}

export function useCosts() {
  return useQuery({ queryKey: keys.costs, queryFn: () => api.get<Costs>('/costs') });
}

export function useHealth() {
  return useQuery({ queryKey: keys.health, queryFn: () => api.get<Health>('/health') });
}

export type { ScenarioRun };
