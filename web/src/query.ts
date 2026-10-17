import { MutationCache, QueryCache, QueryClient } from '@tanstack/react-query';
import { isApiError } from '@/lib/errors';

/**
 * A 401 from any call but the session's own means the session ended (it expired, or the person signed out in
 * another tab): forget who was signed in (keys.me), so RequireAuth sends them to sign in and back again.
 */
export function forgetSessionOn401(error: unknown) {
  if (isApiError(error) && error.isUnauthorized && error.path !== '/me' && error.path !== '/session')
    queryClient.setQueryData(['me'], null);
}

export const queryClient = new QueryClient({
  queryCache: new QueryCache({ onError: forgetSessionOn401 }),
  mutationCache: new MutationCache({ onError: forgetSessionOn401 }),
  defaultOptions: {
    queries: {
      staleTime: 5_000,
      refetchOnWindowFocus: false,
      // A 4xx is an answer, not a glitch: retrying it only delays the message.
      retry: (failureCount, error) => {
        if (isApiError(error) && error.status >= 400 && error.status < 500) return false;
        return failureCount < 2;
      },
    },
    mutations: { retry: false },
  },
});
