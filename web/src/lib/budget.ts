import type { Budget, LiveStatus, Settings } from '@/api/types';
import { formatUsd } from './format';

/**
 * Whether the model budget resets with the instance every hour rather than at 00:00 UTC: the public demo, where the
 * server reports the live hospital on (`GET /settings` `live.enabled`), resets every hour, so its budget is per reset,
 * never "today".
 */
export const resetsHourly = (s: { live?: LiveStatus } | undefined | null): boolean =>
  s?.live?.enabled === true;

/**
 * The model budget in words (CONTRACTS 9): what has been spent against the cap, and the signed-in user's own share
 * when the site gives each judge one. Elsewhere the cap is the day's (spent since 00:00 UTC); on the public demo
 * (`resetsHourly`) it is per reset, spent since the demo last reset. Null when the server sends no budget.
 */
export function budgetText(
  b: Budget | undefined,
  { resetsHourly: hourly = false }: { resetsHourly?: boolean } = {},
): { today: string; share?: string } | null {
  if (!b) return null;
  const spent = formatUsd(b.spentTodayUsd ?? 0);
  const cap = formatUsd(b.dailyUsd);
  const since = 'since the demo last reset (every hour)';
  const today = hourly
    ? !b.dailyUsd || b.dailyUsd <= 0
      ? `No cap: ${spent} spent on live runs ${since}`
      : b.exhausted
        ? `The ${cap} per reset is spent: live runs wait for the demo's next reset (every hour)`
        : `${spent} of the ${cap} per reset spent on live runs ${since}`
    : !b.dailyUsd || b.dailyUsd <= 0
      ? `No daily cap: ${spent} spent on live runs today`
      : b.exhausted
        ? `Today's ${cap} is spent: live runs wait for the reset at 00:00 UTC`
        : `${spent} of today's ${cap} spent on live runs`;
  const share =
    b.perUserUsd && b.perUserUsd > 0
      ? `Your share: ${formatUsd(b.spentByMeUsd ?? 0)} of ${formatUsd(b.perUserUsd)}${hourly ? ' per reset' : ''}`
      : undefined;
  return { today, share };
}

/** Whether the signed-in user can spend nothing more for now: the cap, or their own share, is used up. */
export function budgetSpent(b: Budget | undefined): boolean {
  if (!b) return false;
  if (b.exhausted || b.shareExhausted) return true;
  return !!b.perUserUsd && b.perUserUsd > 0 && (b.spentByMeUsd ?? 0) >= b.perUserUsd;
}

/** "$15" for a whole figure, "$2.50" otherwise. */
const figure = (n: number) => (Number.isInteger(n) ? `$${n}` : formatUsd(n));

/**
 * The live banner's line about what the author pays for the live agents, figure first: `live.budgetNote` when the server
 * sends it (the demo build's own figure, said alone: the hourly reset makes the instance's spend undercount a daily
 * figure), else the instance's own cap, per hour on the public demo (`resetsHourly`) and per day elsewhere, with what was
 * spent against it so far. Null when neither gives a positive figure.
 */
export function budgetNoteLine(s: Settings | undefined): string | null {
  const note = s?.live?.budgetNote;
  const lead = (amount: number, period: 'day' | 'hour') =>
    `${figure(amount)} ${period === 'hour' ? 'an hour' : 'a day'}, paid by the author, runs the live agents`;
  if (note && Number(note.amountUsd) > 0 && (note.period === 'day' || note.period === 'hour'))
    return `${lead(Number(note.amountUsd), note.period)}.`;
  const b = s?.budget;
  if (!b || !(b.dailyUsd > 0)) return null;
  return `${lead(b.dailyUsd, resetsHourly(s) ? 'hour' : 'day')} (so far: ${formatUsd(b.spentTodayUsd ?? 0)}).`;
}
