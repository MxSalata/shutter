import type { Budget } from '@/api/types';
import { formatUsd } from './format';

/**
 * The day's model budget in words (CONTRACTS 9): what has been spent since 00:00 UTC against the cap, and the signed-in
 * user's own share when the site gives each judge one. Null when the server sends no budget.
 */
export function budgetText(b: Budget | undefined): { today: string; share?: string } | null {
  if (!b) return null;
  const spent = formatUsd(b.spentTodayUsd ?? 0);
  const today =
    !b.dailyUsd || b.dailyUsd <= 0
      ? `No daily cap: ${spent} spent on live runs today`
      : b.exhausted
        ? `Today's ${formatUsd(b.dailyUsd)} is spent: live runs wait for the reset at 00:00 UTC`
        : `${spent} of today's ${formatUsd(b.dailyUsd)} spent on live runs`;
  const share =
    b.perUserUsd && b.perUserUsd > 0
      ? `Your share: ${formatUsd(b.spentByMeUsd ?? 0)} of ${formatUsd(b.perUserUsd)}`
      : undefined;
  return { today, share };
}

/** Whether the signed-in user can spend nothing more today: the day's cap, or their own share, is used up. */
export function budgetSpent(b: Budget | undefined): boolean {
  if (!b) return false;
  if (b.exhausted || b.shareExhausted) return true;
  return !!b.perUserUsd && b.perUserUsd > 0 && (b.spentByMeUsd ?? 0) >= b.perUserUsd;
}
