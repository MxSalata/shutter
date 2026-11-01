import { describe, expect, it } from 'vitest';
import { budgetSpent, budgetText } from './budget';

describe("the day's model budget in words", () => {
  it('says nothing when the server sends no budget', () => {
    expect(budgetText(undefined)).toBeNull();
    expect(budgetSpent(undefined)).toBe(false);
  });

  it('reads no cap, a cap partly spent and a cap used up', () => {
    expect(budgetText({ dailyUsd: 0, spentTodayUsd: 1.5, exhausted: false })?.today).toBe(
      'No daily cap: $1.50 spent on live runs today',
    );
    expect(budgetText({ dailyUsd: 15, spentTodayUsd: 4.2, exhausted: false })?.today).toBe(
      "$4.20 of today's $15.00 spent on live runs",
    );
    expect(budgetText({ dailyUsd: 15, spentTodayUsd: 15.1, exhausted: true })?.today).toBe(
      "Today's $15.00 is spent: live runs wait for the reset at 00:00 UTC",
    );
  });

  it("names the caller's share when the site gives each judge one, and counts it as spent at the share", () => {
    const b = { dailyUsd: 15, spentTodayUsd: 4, exhausted: false, perUserUsd: 3, spentByMeUsd: 1.25 };
    expect(budgetText(b)?.share).toBe('Your share: $1.25 of $3.00');
    expect(budgetSpent(b)).toBe(false);
    expect(budgetSpent({ ...b, spentByMeUsd: 3 })).toBe(true);
    expect(budgetText({ ...b, perUserUsd: 0 })?.share).toBeUndefined();
    expect(budgetSpent({ ...b, exhausted: true })).toBe(true);
  });
});
