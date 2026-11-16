import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, seg } from '@/api/client';
import { keys } from '@/api/hooks';
import { isApiError } from '@/lib/errors';
import type {
  SiteEntryContent,
  SiteEntryDetail,
  SiteEntryItem,
  SiteEntryPreview,
  SiteEntryProofResult,
  SiteEntryValidation,
} from '@/api/types';

/**
 * The routes of the site's own scenarios that only the page's workbench uses (CONTRACTS 6.8), kept out of the shared
 * hooks so the entry chunk never carries them. Every change sends what a person wrote and nothing that decides: the
 * entry has no field for who decides or the outcome, and the core answers what would lead and what each case would do.
 */

/** What a person writes: the content without the id Shutter gives, the fixtures as {case, expect}. */
export type EntryBody = Omit<SiteEntryContent, 'id' | 'kind' | 'fixtures'> & {
  fixtures: { case: string; expect: 'match' | 'no_match' }[];
};

export type Action = 'activate' | 'retire' | 'resume';

/** The version an action is about, with its digest and content: activate the draft's, retire and resume the active one's. */
export function versionOf(
  entry: SiteEntryDetail,
  action: Action,
): { version: number; digest: string; content?: SiteEntryContent; writtenBy?: string } | undefined {
  const n = action === 'activate' ? entry.draftVersion : entry.activeVersion;
  if (!n) return undefined;
  const v = entry.versions.find((x) => x.version === n);
  const content =
    action === 'activate'
      ? (entry.draft?.content ?? (entry.activeVersion ? undefined : entry.content))
      : entry.content;
  return v ? { version: n, digest: v.digest, content, writtenBy: v.writtenBy } : undefined;
}

/**
 * The entry as the matcher holds it for an action: a retirement or a resumption is about the active version as it is
 * matched now, with what a recheck dropped left out (effectivePattern, effectiveScope), and the core proves it so.
 */
export function inForce(
  entry: SiteEntryItem,
  action: Action,
  content?: SiteEntryContent,
): SiteEntryContent | undefined {
  if (!content || action === 'activate' || (!entry.effectivePattern && !entry.effectiveScope)) return content;
  return {
    ...content,
    pattern: entry.effectivePattern ?? content.pattern,
    scope: entry.effectiveScope ?? content.scope,
  };
}

const entryKey = (id: string) => ['site-entry', id] as const;

/** One entry with its versions, proofs and events. */
export function useSiteEntry(id: string | undefined) {
  return useQuery({
    queryKey: entryKey(id ?? ''),
    queryFn: () => api.get<SiteEntryDetail>(`/site-entries/${seg(id!)}`),
    enabled: !!id,
  });
}

/** POST /site-entries/preview: stores nothing, so any reader of the page may run it (R16). */
export const preview = (
  body: Partial<EntryBody> & { fromCase?: string; id?: string; action?: Action },
  signal?: AbortSignal,
) => api.post<SiteEntryPreview>('/site-entries/preview', body, { signal });

/** POST /site-entries/validate: what a pattern can displace, for the dialogs. Stores nothing and reads no case. */
export function useValidation(body: Partial<EntryBody> | undefined) {
  return useQuery({
    queryKey: ['site-entry-validate', body ? JSON.stringify({ ...body, fixtures: [] }) : ''],
    queryFn: () => api.post<SiteEntryValidation>('/site-entries/validate', { ...body, fixtures: [] }),
    enabled: !!body,
    staleTime: 60_000,
  });
}

/** After any change: the list, and the entry itself. */
function useRefresh() {
  const client = useQueryClient();
  return async (id?: string) => {
    await client.invalidateQueries({ queryKey: keys.siteEntries });
    if (id) await client.invalidateQueries({ queryKey: entryKey(id) });
  };
}

/** A new draft (201), or the draft changed with the revision read (409 stale_version otherwise). */
export function useSaveDraft() {
  const refresh = useRefresh();
  return useMutation({
    mutationFn: ({ id, revision, body }: { id?: string; revision?: number; body: EntryBody }) =>
      id
        ? api.put<SiteEntryDetail>(`/site-entries/${seg(id)}`, { ...body, expectedVersion: revision })
        : api.post<SiteEntryDetail>('/site-entries', body),
    onSuccess: (entry) => refresh(entry.id),
  });
}

/** Runs the proof of an action and keeps it. */
export function useProve(id: string) {
  const refresh = useRefresh();
  return useMutation({
    mutationFn: (action: Action) =>
      api.post<SiteEntryProofResult>(`/site-entries/${seg(id)}/proof`, { action }),
    onSuccess: () => refresh(id),
  });
}

/** What a proposal or a suspension names: the version and digest the person read, or the entry's revision. */
export interface Read {
  action: Action;
  version: number;
  digest: string;
}

/** Sends an action for approval, naming the version and digest the dialog showed (409 digest_mismatch otherwise). */
export function usePropose(id: string) {
  const refresh = useRefresh();
  return useMutation({
    mutationFn: (read: Read) => api.post<SiteEntryDetail>(`/site-entries/${seg(id)}/propose`, read),
    onSuccess: () => refresh(id),
  });
}

export interface Decision {
  action: Action;
  version: number;
  digest: string;
  decision: 'approve' | 'reject';
  reason: string;
  safetyReference?: string;
}

/** The answer to an approval: the entry, with the new catalogue version and how many waiting plans it stopped. */
export type Decided = SiteEntryDetail & {
  catalogueVersion?: string;
  waitingPlans?: number;
  approver?: string;
};

/** A second person's decision: the action, version and digest they read, as the proposal holds them (R7). */
export function useDecide(id: string) {
  const refresh = useRefresh();
  return useMutation({
    mutationFn: (d: Decision) => api.post<Decided>(`/site-entries/${seg(id)}/approvals`, d),
    onSettled: () => refresh(id),
  });
}

/** Suspends the active entry, naming the revision the person read (409 stale_version otherwise). */
export function useSuspend(id: string) {
  const refresh = useRefresh();
  return useMutation({
    mutationFn: ({ reason, expectedVersion }: { reason: string; expectedVersion: number }) =>
      api.post<SiteEntryDetail>(`/site-entries/${seg(id)}/suspend`, { reason, expectedVersion }),
    onSettled: () => refresh(id),
  });
}

/** The words for a refusal of a change made on what the person read: someone changed the entry since. */
export function changedWords(e: unknown, fallback: string): string {
  return isApiError(e) && (e.code === 'digest_mismatch' || e.code === 'stale_version')
    ? 'Someone changed this entry since you opened it: close and open it again.'
    : fallback;
}
