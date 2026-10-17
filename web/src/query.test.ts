import { describe, expect, it } from 'vitest';
import { ApiError } from '@/lib/errors';
import { forgetSessionOn401, queryClient } from './query';

const unauthorized = (path: string) => new ApiError({ status: 401, method: 'GET', path, body: null });

describe('forgetSessionOn401', () => {
  it('signs the person out when a page call says the session ended', () => {
    queryClient.setQueryData(['me'], { username: 'approver' });
    forgetSessionOn401(unauthorized('/cases'));
    expect(queryClient.getQueryData(['me'])).toBeNull();
  });

  it('leaves the session alone for a wrong password or the session check itself', () => {
    queryClient.setQueryData(['me'], { username: 'approver' });
    forgetSessionOn401(unauthorized('/session'));
    forgetSessionOn401(unauthorized('/me'));
    forgetSessionOn401(new ApiError({ status: 403, method: 'GET', path: '/cases', body: null }));
    expect(queryClient.getQueryData(['me'])).toEqual({ username: 'approver' });
  });
});
