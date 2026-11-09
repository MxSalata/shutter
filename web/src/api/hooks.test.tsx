import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from './client';
import { keys, useCasesOnce, useDecideApproval } from './hooks';

const client = () => new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 5_000 } } });
const wrapper =
  (c: QueryClient) =>
  ({ children }: { children: ReactNode }) => <QueryClientProvider client={c}>{children}</QueryClientProvider>;

afterEach(() => {
  vi.restoreAllMocks();
});

describe('useCasesOnce', () => {
  it('reads the list once: its query is never stale, so a remount asks nothing more', async () => {
    const get = vi.spyOn(api, 'get').mockResolvedValue({ items: [], total: 0 });
    const c = client();
    const filters = { scenario: 'S8', limit: 100 };
    const first = renderHook(() => useCasesOnce(filters), { wrapper: wrapper(c) });
    await waitFor(() => expect(first.result.current.isSuccess).toBe(true));
    const observer = c.getQueryCache().find({ queryKey: keys.cases(filters) })?.observers[0];
    expect(observer?.options.staleTime).toBe(Infinity);
    first.unmount();
    const again = renderHook(() => useCasesOnce(filters), { wrapper: wrapper(c) });
    await waitFor(() => expect(again.result.current.isSuccess).toBe(true));
    expect(get).toHaveBeenCalledTimes(1);
  });

  it('reads the list again after a decision on a held case', async () => {
    const get = vi.spyOn(api, 'get').mockResolvedValue({ items: [], total: 0 });
    vi.spyOn(api, 'post').mockResolvedValue({
      taskId: 't',
      decision: 'approve',
      caseId: 'C1',
      approver: 'a',
    });
    const c = client();
    const filters = { state: 'awaiting_approval', scenario: 'S2', limit: 1 } as const;
    const home = renderHook(() => useCasesOnce(filters), { wrapper: wrapper(c) });
    await waitFor(() => expect(home.result.current.isSuccess).toBe(true));
    home.unmount();
    const decide = renderHook(() => useDecideApproval('C1'), { wrapper: wrapper(c) });
    await act(() =>
      decide.result.current.mutateAsync({
        decision: { decision: 'approve', planDigest: 'd', expectedVersion: 1, comment: '' },
        idempotencyKey: 'k',
      }),
    );
    expect(get).toHaveBeenCalledTimes(1);
    renderHook(() => useCasesOnce(filters), { wrapper: wrapper(c) });
    await waitFor(() => expect(get).toHaveBeenCalledTimes(2));
  });
});
