import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, seg } from '@/api/client';

/**
 * The Settings screen's calls for watched namespaces (CONTRACTS 11.1). The plan's own shape is the helper's, in its
 * snake_case, since the screen shows the helper's sentences as they are.
 */
export interface WatchedNamespace {
  namespace: string;
  onboarded: boolean;
  exists: boolean;
  production: string;
  production_state: string;
  forwarder: boolean;
  alert_intake: boolean;
  credential: boolean;
  last_forward: string;
  last_case: string;
  last_case_at: string;
  removed: boolean;
  problems: string[];
  ok: boolean;
}

export interface NamespaceList {
  shutterNamespace: string;
  /** Whether this user holds %Admin_Manage, which an apply and a removal need. */
  canApply: boolean;
  watched: WatchedNamespace[];
  available: { namespace: string }[];
  /** The trial's recording, when these answers are a replay of one. */
  recordedAt?: string;
}

export interface PlanAction {
  do: string;
  says: string;
}

export interface PlanOperation {
  name: string;
  reported_as: string;
  proves: string;
  alert_on_error: boolean;
}

export interface NamespacePlan {
  namespace: string;
  production: string;
  production_state: string;
  onboarded: boolean;
  operations: PlanOperation[];
  actions: PlanAction[];
  todo: string[];
  warnings: string[];
  error: string;
  wired: { credential: boolean };
}

/** A plan, with the digest an apply must bring back. */
export interface PlanAnswer {
  plan: NamespacePlan;
  digest: string;
}

export interface ApplyAnswer {
  ok: boolean;
  changed: string[];
  unchanged: string;
  todo: string[];
  warnings: string[];
  error: string;
}

export interface TestAnswer {
  ok: boolean;
  case: string;
  http_status: string | number;
  advice: string;
  error: string;
}

export interface RemovalPreview {
  namespace: string;
  onboarded: boolean;
  production: string;
  renamed: string;
  items: string[];
  alertOnError: string[];
  mappings: string[];
  drafted: string[];
}

export interface RemoveAnswer {
  ok: boolean;
  removed: string[];
  kept: string[];
  error: string;
}

/** The options a plan may be read with; an empty one is as if not given. */
export interface PlanOptions {
  production?: string;
  receivers?: string;
  alert_on_error?: boolean;
  shutter_host?: string;
  shutter_port?: string;
  ssl_config?: string;
  credential?: string;
}

const LIST = ['settings', 'namespaces'] as const;
const path = (ns: string, what: string) => `/settings/namespaces/${seg(ns)}/${what}`;

export function useNamespaces(enabled: boolean) {
  return useQuery({
    queryKey: LIST,
    queryFn: () => api.get<NamespaceList>('/settings/namespaces'),
    enabled,
  });
}

export function useReadPlan() {
  return useMutation({
    mutationFn: ({ ns, options }: { ns: string; options: PlanOptions }) =>
      api.post<PlanAnswer>(path(ns, 'plan'), { options }),
  });
}

/** Runs the plan the digest names and no other; a plan that has moved answers 409 `plan_changed` with the new one. */
export function useApplyPlan() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ ns, options, digest }: { ns: string; options: PlanOptions; digest: string }) =>
      api.post<ApplyAnswer>(path(ns, 'apply'), { options, digest }),
    onSettled: () => client.invalidateQueries({ queryKey: LIST }),
  });
}

export function useSendTest() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (ns: string) => api.post<TestAnswer>(path(ns, 'test')),
    onSettled: () => client.invalidateQueries({ queryKey: LIST }),
  });
}

export function useRemovalPreview(ns: string | null) {
  return useQuery({
    queryKey: [...LIST, ns, 'removal'],
    queryFn: () => api.get<RemovalPreview>(path(ns ?? '', 'removal')),
    enabled: ns !== null,
  });
}

export function useRemove() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ ns, unmap, credential }: { ns: string; unmap: boolean; credential: boolean }) =>
      api.post<RemoveAnswer>(path(ns, 'remove'), { unmap, credential }),
    onSettled: () => client.invalidateQueries({ queryKey: LIST }),
  });
}

/** The terminal command for the forwarder's sign-in: the password never passes through the app. */
export const credentialCommand = (ns: string) => `Do ##class(Shutter.Setup).OnboardCredential("${ns}")`;

/** The options as they are sent: what is empty is left out, so the digest reads the same as with none. */
export function usedOptions(o: PlanOptions): PlanOptions {
  return Object.fromEntries(
    Object.entries(o).filter(([, v]) => v !== '' && v !== false && v !== undefined),
  ) as PlanOptions;
}
