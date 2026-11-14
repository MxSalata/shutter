import { describe, expect, it } from 'vitest';
import type { Budget, LiveAgents, Settings } from '@/api/types';
import { bannerBudgetNote, budgetNoteLine } from './budget';
import { ApiError } from './errors';
import {
  INSTALL_LEAD,
  INSTALL_URL,
  STILL_WORKS,
  budgetLimit,
  liveRefusal,
  liveRefusalInText,
  liveUnavailable,
  liveUnavailableWords,
} from './liveAgents';

// 19:20 GMT on 2 Nov 2026: the demo's next hourly reset is due at 20:00, the day's at 00:00 UTC
const NOW = Date.parse('2026-11-02T19:20:00Z');
const NEXT_HOUR = '2026-11-02T20:00:00Z';
const MIDNIGHT = '2026-11-03T00:00:00Z';

const spent: Budget = {
  dailyUsd: 2,
  spentTodayUsd: 2.1,
  exhausted: true,
  resetsAt: MIDNIGHT,
  perUserUsd: 0,
  spentByMeUsd: 0,
  shareExhausted: false,
};
/** The caller's own share used up, the cap not: the server marks `exhausted` too (Budget.StatusFor). */
const share: Budget = {
  dailyUsd: 2,
  spentTodayUsd: 1,
  exhausted: true,
  resetsAt: MIDNIGHT,
  perUserUsd: 1,
  spentByMeUsd: 1,
  shareExhausted: true,
};

/** Settings as a server sends them: the public demo (`live.enabled`, hourly), a demo instance, or another site. */
function settings({
  budget,
  agents,
  hourly = false,
  demo = hourly,
  budgetNote,
}: {
  budget?: Budget;
  agents?: LiveAgents;
  hourly?: boolean;
  demo?: boolean;
  budgetNote?: { amountUsd: number; period: 'day' | 'hour' };
}): Settings {
  return {
    mode: 'board',
    scenario: '',
    resetAt: '',
    demo,
    agentItems: [],
    prices: [],
    aiHubPresent: true,
    liveRunnerPresent: true,
    live: { enabled: hourly, ...(agents ? { agents } : {}), ...(budgetNote ? { budgetNote } : {}) },
    ...(budget ? { budget } : {}),
  };
}

const lead = (s: Settings) => {
  const u = liveUnavailable(s);
  return u ? liveUnavailableWords(u, NOW).lead : null;
};

describe('whether the live agents can run, without live.agents (a server before v1.37)', () => {
  it('reads the cap used up as the budget, and nothing while it is not', () => {
    expect(lead(settings({ budget: { ...spent, exhausted: false, spentTodayUsd: 1 } }))).toBeNull();
    expect(lead(settings({}))).toBeNull();
    expect(liveUnavailable(undefined)).toBeNull();
    expect(lead(settings({ budget: spent }))).toBe(
      'The live AI budget for this site is used up until 00:00 UTC.',
    );
  });

  it('says "this demo" and offers the install link on a demo instance, daily there', () => {
    const u = liveUnavailable(settings({ budget: spent, demo: true }))!;
    expect(liveUnavailableWords(u, NOW)).toEqual({
      lead: 'The live AI budget for this demo is used up until 00:00 UTC.',
      still: STILL_WORKS,
      install: INSTALL_LEAD,
    });
    expect(STILL_WORKS).toBe('Open cases, recorded runs and the trial still work.');
    expect(INSTALL_LEAD).toBe('To run the live agents yourself, install Shutter with your own API key:');
    // Another site was installed by its reader: no install link there
    expect(liveUnavailableWords(liveUnavailable(settings({ budget: spent }))!, NOW).install).toBeNull();
  });

  it('says the hourly reset on the public demo, with its time when the server gives one within the hour', () => {
    expect(lead(settings({ budget: { ...spent, resetsAt: NEXT_HOUR }, hourly: true }))).toBe(
      'The live AI budget for this demo is used up until 20:00 GMT, when the demo resets.',
    );
    // The server's next 00:00 UTC comes after the demo's own reset, so it is not said
    expect(lead(settings({ budget: spent, hourly: true }))).toBe(
      "The live AI budget for this demo is used up until the demo's next reset, within the hour.",
    );
    expect(lead(settings({ budget: { ...spent, resetsAt: undefined }, hourly: true }))).toBe(
      "The live AI budget for this demo is used up until the demo's next reset, within the hour.",
    );
  });

  it("keeps the caller's own share apart from the cap", () => {
    expect(budgetLimit(share)).toBe('share');
    expect(budgetLimit(spent)).toBe('budget');
    // Both spent: the cap is what everyone meets
    expect(budgetLimit({ ...share, spentTodayUsd: 2 })).toBe('budget');
    // An older server without shareExhausted: the share by its figures
    expect(budgetLimit({ ...share, exhausted: false, shareExhausted: undefined })).toBe('share');
    expect(budgetLimit({ ...share, exhausted: false, shareExhausted: false, spentByMeUsd: 0.5 })).toBeNull();
    expect(lead(settings({ budget: share }))).toBe(
      'Your share of the live budget is used up until 00:00 UTC.',
    );
    expect(lead(settings({ budget: { ...share, resetsAt: NEXT_HOUR }, hourly: true }))).toBe(
      'Your share of the live budget is used up until 20:00 GMT, when the demo resets.',
    );
    expect(liveUnavailable(settings({ budget: share }))?.code).toBe('budget.shareExhausted');
  });
});

describe('whether the live agents can run, from live.agents (v1.37)', () => {
  it('answers from live.agents when the server sends it, whatever the budget says', () => {
    expect(
      lead(settings({ budget: spent, agents: { available: true, reason: null, until: null } })),
    ).toBeNull();
    expect(
      lead(settings({ budget: spent, agents: { available: false, reason: 'budget', until: MIDNIGHT } })),
    ).toBe('The live AI budget for this site is used up until 00:00 GMT.');
  });

  it('takes the provider\'s time from until, never the demo\'s hourly reset, and says "for now" without one', () => {
    const down = { available: false, reason: 'provider_auth', until: MIDNIGHT } as const;
    expect(lead(settings({ agents: down, hourly: true }))).toBe(
      'The live AI service for this demo is unavailable until 00:00 GMT.',
    );
    expect(lead(settings({ agents: { ...down, until: null }, hourly: true }))).toBe(
      'The live AI service for this demo is unavailable for now.',
    );
    // A time already past is no promise
    expect(lead(settings({ agents: { ...down, until: '2026-11-02T19:00:00Z' }, hourly: true }))).toBe(
      'The live AI service for this demo is unavailable for now.',
    );
    // A day or more away carries its day
    expect(lead(settings({ agents: { ...down, until: '2026-11-04T00:00:00Z' }, demo: true }))).toBe(
      'The live AI service for this demo is unavailable until 4 Nov, 00:00 GMT.',
    );
    // A reason the app does not know reads as the service
    expect(lead(settings({ agents: { available: false, reason: null, until: null }, demo: true }))).toBe(
      'The live AI service for this demo is unavailable for now.',
    );
  });

  it('words the budget on the public demo by its next reset, the server giving the next 00:00 UTC', () => {
    expect(
      lead(
        settings({
          budget: spent,
          agents: { available: false, reason: 'budget', until: MIDNIGHT },
          hourly: true,
        }),
      ),
    ).toBe("The live AI budget for this demo is used up until the demo's next reset, within the hour.");
    expect(
      lead(
        settings({
          budget: spent,
          agents: { available: false, reason: 'budget', until: NEXT_HOUR },
          hourly: true,
        }),
      ),
    ).toBe('The live AI budget for this demo is used up until 20:00 GMT, when the demo resets.');
    expect(
      lead(
        settings({ budget: spent, agents: { available: false, reason: 'budget', until: null }, demo: true }),
      ),
    ).toBe('The live AI budget for this demo is used up for now.');
  });

  it("reads the caller's share from the budget when live.agents says budget", () => {
    expect(
      lead(
        settings({
          budget: share,
          agents: { available: false, reason: 'budget', until: MIDNIGHT },
          demo: true,
        }),
      ),
    ).toBe('Your share of the live budget is used up until 00:00 GMT.');
  });

  it("reads the caller's share from the server's sentence when the next run's estimate no longer fits it", () => {
    // 1.60 of a 2.00 share spent and a 0.50 estimate: refused, while neither figure says spent
    const short: Budget = {
      ...share,
      exhausted: false,
      shareExhausted: false,
      perUserUsd: 2,
      spentByMeUsd: 1.6,
    };
    const detail =
      "Your share of the day's model budget, 2.00 USD, has 0.40 USD left (1.60 USD spent since 2026-11-02T00:00:00Z), less than a run's estimate of 0.50 USD; the run was not sent. It resets at 2026-11-03T00:00:00Z.";
    expect(budgetLimit(short)).toBeNull();
    const u = liveUnavailable(
      settings({
        budget: short,
        agents: { available: false, reason: 'budget', until: MIDNIGHT, detail },
        demo: true,
      }),
    )!;
    expect(u.reason).toBe('share');
    expect(liveUnavailableWords(u, NOW).lead).toBe(
      'Your share of the live budget is used up until 00:00 GMT.',
    );
    expect(u.detail).toBe(detail);
    // The cap's own estimate refusal stays the budget
    const cap = liveUnavailable(
      settings({
        budget: { ...short, perUserUsd: 0, spentByMeUsd: 0 },
        agents: {
          available: false,
          reason: 'budget',
          until: MIDNIGHT,
          detail:
            "The day's model budget of 2.00 USD has 0.10 USD left (1.90 USD spent since 2026-11-02T00:00:00Z), less than a run's estimate of 0.50 USD; the run was not sent.",
        },
        demo: true,
      }),
    )!;
    expect(cap.reason).toBe('budget');
    expect(liveUnavailableWords(cap, NOW).lead).toBe(
      'The live AI budget for this demo is used up until 00:00 GMT.',
    );
  });

  it("keeps the server's sentence for Technical", () => {
    const u = liveUnavailable(
      settings({
        agents: { available: false, reason: 'provider_auth', until: MIDNIGHT, detail: 'The key was refused' },
      }),
    )!;
    expect(u.code).toBe('live.agents.reason provider_auth');
    expect(u.detail).toBe('The key was refused');
    expect(liveUnavailableWords(u, NOW).lead).not.toContain('refused');
  });
});

const refusal = (status: number, body: unknown) =>
  new ApiError({ status, method: 'POST', path: '/cases/C-000008/board', body });

describe('a live call the server refused', () => {
  it('reads 409 live_unavailable with its live object, its reason and until', () => {
    const u = liveRefusal(
      refusal(409, {
        error: 'live_unavailable',
        detail: 'The model provider refused the key',
        live: { available: false, reason: 'provider_auth', until: MIDNIGHT, detail: 'x' },
      }),
      settings({ demo: true }),
    )!;
    expect(liveUnavailableWords(u, NOW).lead).toBe(
      'The live AI service for this demo is unavailable until 00:00 GMT.',
    );
    expect(u.code).toBe('409 live_unavailable');
    expect(u.detail).toBe('The model provider refused the key');
  });

  it('reads the reason at the top of the body too, and live.agents for a time the body leaves out', () => {
    const agents = { available: false, reason: 'provider_auth', until: MIDNIGHT } as const;
    const u = liveRefusal(
      refusal(409, { error: 'live_unavailable', reason: 'provider_auth' }),
      settings({ agents }),
    )!;
    expect(liveUnavailableWords(u, NOW).lead).toBe(
      'The live AI service for this site is unavailable until 00:00 GMT.',
    );
    expect(
      liveUnavailableWords(liveRefusal(refusal(409, { error: 'live_unavailable' }), settings({}))!, NOW).lead,
    ).toBe('The live AI service for this site is unavailable for now.');
  });

  it('reads 409 budget_exhausted as the budget, or the share, as live_unavailable is', () => {
    const cap = liveRefusal(
      refusal(409, { error: 'budget_exhausted', detail: 'spent', budget: spent }),
      settings({}),
    )!;
    expect(cap.reason).toBe('budget');
    expect(liveUnavailableWords(cap, NOW).lead).toBe(
      'The live AI budget for this site is used up until 00:00 UTC.',
    );
    // The settings read before the press said nothing was spent; the refusal's own words say whose
    const mine = liveRefusal(
      refusal(409, { error: 'budget_exhausted', detail: "Your share of today's model budget is spent" }),
      settings({ budget: { ...share, exhausted: false, shareExhausted: false, spentByMeUsd: 0.5 } }),
    )!;
    expect(liveUnavailableWords(mine, NOW).lead).toBe(
      'Your share of the live budget is used up until 00:00 UTC.',
    );
    // With live.agents, the time is the server's
    const withAgents = liveRefusal(
      refusal(409, { error: 'budget_exhausted', detail: 'spent', budget: spent }),
      settings({ agents: { available: false, reason: 'budget', until: MIDNIGHT } }),
    )!;
    expect(liveUnavailableWords(withAgents, NOW).lead).toBe(
      'The live AI budget for this site is used up until 00:00 GMT.',
    );
  });

  it('leaves every other error alone', () => {
    expect(
      liveRefusal(refusal(409, { error: 'wrong_state', detail: 'The case is resolved' }), settings({})),
    ).toBeNull();
    expect(liveRefusal(refusal(403, { error: 'live_unavailable' }), settings({}))).toBeNull();
    expect(liveRefusal(new Error('budget_exhausted'), settings({}))).toBeNull();
    expect(liveRefusal(null, settings({}))).toBeNull();
  });
});

describe("a question's failure read from its error", () => {
  it('reads the budget, the share and the provider from what the server wrote', () => {
    const s = settings({ demo: true });
    const cap = liveRefusalInText(
      "The agent answered budget_exhausted: The day's model budget of 2.00 USD is spent (2.10 USD since 2026-11-02T00:00:00Z); the run was not sent.",
      s,
    )!;
    expect(cap.reason).toBe('budget');
    expect(cap.detail).toContain('budget_exhausted');
    expect(
      liveRefusalInText(
        "No member answered usably: conformance: budget_exhausted (Your share of the day's model budget, 1.00 USD, is spent)",
        s,
      )?.reason,
    ).toBe('share');
    expect(
      liveRefusalInText(
        "The agent answered provider_auth: The model provider refused Shutter's key at 19:00",
        s,
      )?.reason,
    ).toBe('service');
    expect(
      liveRefusalInText('Error from the agent call: authentication_error: invalid x-api-key', s)?.reason,
    ).toBe('service');
    expect(liveRefusalInText('Error from the agent call: This API key has been disabled', s)?.reason).toBe(
      'service',
    );
    // The budget's own sentence without its code
    expect(
      liveRefusalInText("Your share of the day's model budget, 1.00 USD, is spent (1.02 USD since 00:00)", s)
        ?.reason,
    ).toBe('share');
    expect(liveRefusalInText('No answer: the run timed out', s)).toBeNull();
    expect(liveRefusalInText('', s)).toBeNull();
  });

  it('does not read a busy admission as the budget spent: it is an ordinary failure to try again', () => {
    expect(
      liveRefusalInText(
        "The agent answered budget_busy: The day's model budget could not be checked in time (another run was being admitted); the run was not sent. Try again in a moment.",
        settings({ demo: true }),
      ),
    ).toBeNull();
  });
});

describe("the banner's line about the live budget", () => {
  it("says the demo build's own figure alone when the server sends it", () => {
    expect(budgetNoteLine(settings({ budget: spent, budgetNote: { amountUsd: 15, period: 'day' } }))).toBe(
      "$15 a day from the author runs the judges' live agents.",
    );
    expect(budgetNoteLine(settings({ budgetNote: { amountUsd: 2.5, period: 'hour' } }))).toBe(
      "$2.50 an hour from the author runs the judges' live agents.",
    );
  });

  it("reads the instance's own cap otherwise, per hour on the public demo, with what was spent so far", () => {
    expect(
      budgetNoteLine(settings({ budget: { ...spent, spentTodayUsd: 0.4, exhausted: false }, hourly: true })),
    ).toBe("$2 an hour from the author runs the judges' live agents (so far: $0.40).");
    expect(budgetNoteLine(settings({ budget: { ...spent, dailyUsd: 15, spentTodayUsd: 4.2 } }))).toBe(
      "$15 a day from the author runs the judges' live agents (so far: $4.20).",
    );
    // A note with no positive figure is no note
    expect(
      budgetNoteLine(
        settings({ budget: { ...spent, spentTodayUsd: 0 }, budgetNote: { amountUsd: 0, period: 'day' } }),
      ),
    ).toBe("$2 a day from the author runs the judges' live agents (so far: $0.00).");
  });

  it('says nothing when neither gives a positive figure', () => {
    expect(budgetNoteLine(settings({}))).toBeNull();
    expect(budgetNoteLine(settings({ budget: { ...spent, dailyUsd: 0 } }))).toBeNull();
    expect(budgetNoteLine(undefined)).toBeNull();
  });
});

describe("who reads the banner's line about the live budget", () => {
  const judges = { liveAgents: true };
  const demo = { liveAgents: false };

  it('gives it to an account that runs the live agents, the same line in both forms', () => {
    const note = settings({ budgetNote: { amountUsd: 15, period: 'day' } });
    expect(bannerBudgetNote(note, judges)).toBe("$15 a day from the author runs the judges' live agents.");
    const cap = settings({ budget: { ...spent, spentTodayUsd: 0.4, exhausted: false }, hourly: true });
    expect(bannerBudgetNote(cap, judges)).toBe(budgetNoteLine(cap));
    expect(bannerBudgetNote(cap, judges)).toBe(
      "$2 an hour from the author runs the judges' live agents (so far: $0.40).",
    );
  });

  it('gives nothing to an account without them, whatever figure the server sends', () => {
    expect(bannerBudgetNote(settings({ budgetNote: { amountUsd: 15, period: 'day' } }), demo)).toBeNull();
    expect(
      bannerBudgetNote(settings({ budget: { ...spent, exhausted: false }, hourly: true }), demo),
    ).toBeNull();
    // The notice that the live agents cannot run is not this line: it still reads the same settings for everyone
    const out = settings({ budget: spent, hourly: true, budgetNote: { amountUsd: 15, period: 'day' } });
    expect(bannerBudgetNote(out, demo)).toBeNull();
    expect(liveUnavailable(out)?.reason).toBe('budget');
  });

  it('gives nothing to either when no positive figure is sent', () => {
    expect(bannerBudgetNote(settings({}), judges)).toBeNull();
    expect(bannerBudgetNote(undefined, judges)).toBeNull();
    expect(bannerBudgetNote(settings({}), demo)).toBeNull();
  });
});

it('links to the README\'s "Try it" from one constant', () => {
  expect(INSTALL_URL).toBe('https://github.com/MxSalata/shutter#try-it');
});
