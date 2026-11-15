import { describe, expect, it } from 'vitest';
import type { Can, RecoveryControl, Settings, SiteProfile } from '@/api/types';
import {
  stateOf,
  taskReadiness,
  type ConditionCode,
  type ReadinessInput,
  type TaskId,
  type TaskReadiness,
} from './tasks';

const NOW = Date.parse('2026-11-15T14:00:00Z');
const AT = '2026-11-15T13:59:30.000Z';
const MIDNIGHT = '2026-11-16T00:00:00Z';

const ALL: Can = {
  operate: true,
  approve: true,
  configure: true,
  scenarios: true,
  reset: true,
  stopRecovery: true,
  liveAgents: true,
};
const NOTHING: Can = {
  operate: false,
  approve: false,
  configure: false,
  scenarios: false,
  reset: false,
  liveAgents: false,
};
/** An operator: operates and runs scenarios, may not approve or change the site. */
const OPERATOR: Can = { ...ALL, approve: false, configure: false };
/** The public demo's own user: approves and operates, runs scenarios from recordings, spends no budget. */
const DEMO: Can = { ...ALL, configure: false, reset: false, liveAgents: false };

const settings = (over: Partial<Settings> = {}): Settings => ({
  agentMode: 'auto',
  providerConfigured: true,
  mode: 'board',
  scenario: '',
  resetAt: '',
  demo: true,
  agentItems: [
    {
      name: 'Agent Coordinator',
      enabled: true,
      agentClass: 'Shutter.Agent.Coordinator',
      mode: 'auto',
      effectiveMode: 'live',
    },
  ],
  prices: [],
  aiHubPresent: true,
  liveRunnerPresent: true,
  mock: false,
  ...over,
});

const RECOVERY: RecoveryControl = {
  mode: 'enabled',
  generation: 1,
  stopped: false,
  stoppedAt: '',
  stoppedBy: '',
  stopReason: '',
  outstanding: [],
  outstandingCount: 0,
  readable: true,
  covers: '',
  doesNotCover: '',
};

const profile = (over: Partial<SiteProfile> = {}): SiteProfile => ({
  receivers: [],
  policy: {},
  recovery: { mode: 'enabled' },
  ...over,
});

/** A live instance, fully set up, signed in as an approver who may change the site. */
const live = (over: Partial<ReadinessInput> = {}): ReadinessInput => ({
  trial: false,
  signedIn: true,
  can: ALL,
  settings: settings(),
  settingsAt: AT,
  recovery: RECOVERY,
  recoveryAt: AT,
  profile: profile(),
  profileAt: AT,
  liveRuns: 12,
  now: NOW,
  ...over,
});

const tasks = (i: ReadinessInput) =>
  Object.fromEntries(taskReadiness(i).map((t) => [t.id, t])) as Record<TaskId, TaskReadiness>;
const codes = (t: TaskReadiness): ConditionCode[] => t.conditions.map((c) => c.code);

describe('taskReadiness', () => {
  it('gives six tasks in the order a person meets them, all ready on a demo set up for an approver', () => {
    const all = taskReadiness(live());
    expect(all.map((t) => t.id)).toEqual(['read', 'scenario', 'ask', 'approve', 'escalate', 'close']);
    for (const t of all) {
      expect(t.state, t.id).toBe('ready');
      expect(t.conditions, t.id).toEqual([]);
    }
  });

  it('keeps what is set up, what holds now and what was seen apart, with the time the page read each', () => {
    const { ask, approve, scenario } = tasks(live());
    expect(ask.evidence).toEqual([
      { kind: 'set up', words: 'A model key is configured.' },
      { kind: 'now', words: 'The model can be asked.', at: AT },
      { kind: 'seen', words: '12 agent runs reached a real model on this instance.' },
    ]);
    expect(approve.evidence).toEqual([{ kind: 'now', words: 'Recovery is enabled, not stopped.', at: AT }]);
    expect(scenario.evidence[0]).toMatchObject({ kind: 'set up', at: AT });
    expect(scenario.evidence[0].words).toMatch(/call the model/);
    expect(tasks(live({ liveRuns: 0 })).ask.evidence[2].words).toBe(
      'No agent run has reached a real model on this instance yet.',
    );
  });

  it("says the last observed live call from the health report, with when it started, in place of the costs' count", () => {
    const STARTED = '2026-11-15T09:12:00Z';
    const ok = tasks(live({ lastLive: { at: STARTED, status: 'ok' } })).ask;
    expect(ok.evidence[2]).toEqual({
      kind: 'seen',
      words: 'The newest run that reached a real model answered.',
      started: STARTED,
    });
    expect(ok.evidence).toHaveLength(3);
    // A failing afternoon shows as such beside the configured mode and what holds now
    const failed = tasks(live({ lastLive: { at: STARTED, status: 'model_error' } })).ask;
    expect(failed.evidence.map((e) => e.kind)).toEqual(['set up', 'now', 'seen']);
    expect(failed.evidence[2]).toEqual({
      kind: 'seen',
      words: 'The newest run that reached a real model ended without a usable answer.',
      started: STARTED,
      code: 'model_error',
    });
    expect(failed.state).toBe('ready');
    // None yet, whatever the board's count says
    expect(tasks(live({ lastLive: null })).ask.evidence[2]).toEqual({
      kind: 'seen',
      words: 'No agent run has reached a real model on this instance yet.',
    });
    // It is said with no key too: what was seen stays apart from what is set up
    const noKey = tasks(
      live({ settings: settings({ providerConfigured: false }), lastLive: { at: STARTED, status: 'ok' } }),
    ).ask;
    expect(noKey.evidence.map((e) => e.kind)).toEqual(['set up', 'seen']);
  });

  it('says a run refused before any call was refused, never that it reached a model, with its status kept for Technical', () => {
    const STARTED = '2026-11-15T09:12:00Z';
    const seen = (status: string) => tasks(live({ lastLive: { at: STARTED, status } })).ask.evidence[2];
    const refused = {
      budget_exhausted:
        "The newest run meant for a real model was refused before any call to it: the day's live AI budget, or its requester's share of it, was used up.",
      budget_busy:
        'The newest run meant for a real model was refused before any call to it: the budget could not be checked in time.',
      provider_auth:
        'The newest run meant for a real model was refused before any call to it: the model provider refused the key.',
    };
    for (const [status, words] of Object.entries(refused)) {
      expect(seen(status), status).toEqual({ kind: 'seen', words, started: STARTED, code: status });
      expect(seen(status).words, status).not.toMatch(/reached/);
      // The status as the store keeps it is not in the words
      expect(seen(status).words, status).not.toContain(status);
    }
    // A status of the same name on the object's prototype is not a refusal
    expect(seen('constructor').words).toBe(
      'The newest run that reached a real model ended without a usable answer.',
    );
  });

  describe("the review's acceptance states, each with a truthful next step", () => {
    it('no key: asking is not possible, and the next step names the key and the restart', () => {
      const t = tasks(live({ settings: settings({ providerConfigured: false }) }));
      expect(t.ask.state).toBe('blocked');
      expect(codes(t.ask)).toEqual(['no_key']);
      expect(t.ask.conditions[0].next).toMatch(/ANTHROPIC_API_KEY \(or OPENAI_API_KEY\) in \.env/);
      expect(t.ask.evidence[0].words).toBe('No model key is configured.');
      // A scenario still runs, from its recordings
      expect(t.scenario.state).toBe('limited');
      expect(codes(t.scenario)).toEqual(['replays_only']);
      // The approval does not depend on a model
      expect(t.approve.state).toBe('ready');
    });

    it('no key on the replay edition: the next step is the AI Hub edition, not a key', () => {
      const t = tasks(live({ settings: settings({ providerConfigured: false, aiHubPresent: false }) }));
      expect(codes(t.ask)).toEqual(['replay_edition']);
      expect(t.ask.conditions[0].next).toMatch(/AI Hub edition/);
    });

    it('the API mimic: a question of your own is not now, as the Ask panel says, and nothing claims a model', () => {
      for (const providerConfigured of [false, true]) {
        const t = tasks(live({ settings: settings({ providerConfigured, mock: true }) }));
        expect(t.ask.state, String(providerConfigured)).toBe('blocked');
        expect(codes(t.ask)).toEqual(['mimic']);
        expect(t.ask.conditions[0].next).toMatch(/^Pick a suggested question on a case/);
        expect(t.ask.conditions[0].next).toMatch(/switches the mimic off/);
        expect(t.ask.evidence[0]).toEqual({
          kind: 'set up',
          words: 'The API mimic is on, a test fixture: no model is called.',
        });
        expect(t.ask.evidence.some((e) => e.kind === 'now')).toBe(false);
      }
      // Its scenarios still run, against the mimic
      const scenario = tasks(live({ settings: settings({ mock: true }) })).scenario;
      expect(scenario.state).toBe('ready');
      expect(scenario.evidence[0].words).toMatch(/API mimic/);
    });

    it('provider failure: the existing notice words, until when, and a next step by the instance', () => {
      const failing = settings({
        demo: false,
        live: { enabled: false, agents: { available: false, reason: 'provider_auth', until: MIDNIGHT } },
      });
      const site = tasks(live({ settings: failing }));
      expect(site.ask.state).toBe('blocked');
      expect(codes(site.ask)).toEqual(['provider']);
      expect(site.ask.conditions[0].words).toMatch(
        /^The live AI service for this site is unavailable until /,
      );
      expect(site.ask.conditions[0].next).toMatch(/administrator checks the model key/);
      expect(site.ask.evidence[1]).toEqual({ kind: 'now', words: 'The model cannot be asked.', at: AT });
      const demo = tasks(
        live({ settings: { ...failing, demo: true, live: { ...failing.live!, enabled: true } } }),
      );
      expect(demo.ask.conditions[0].words).toMatch(/^The live AI service for this demo is unavailable/);
      expect(demo.ask.conditions[0].next).toMatch(/install Shutter with your own API key/);
    });

    it("exhausted budget: the cap or the user's share, each with its own next step", () => {
      const capped = tasks(
        live({
          settings: settings({
            demo: false,
            budget: { dailyUsd: 5, spentTodayUsd: 5, exhausted: true, resetsAt: MIDNIGHT },
          }),
        }),
      );
      expect(codes(capped.ask)).toEqual(['budget']);
      expect(capped.ask.conditions[0].words).toBe(
        'The live AI budget for this site is used up until 00:00 UTC.',
      );
      expect(capped.ask.conditions[0].next).toMatch(/SHUTTER_DAILY_BUDGET_USD/);
      const share = tasks(
        live({
          settings: settings({
            demo: false,
            budget: {
              dailyUsd: 50,
              spentTodayUsd: 5,
              exhausted: true,
              perUserUsd: 5,
              spentByMeUsd: 5,
              shareExhausted: true,
              resetsAt: MIDNIGHT,
            },
          }),
        }),
      );
      expect(codes(share.ask)).toEqual(['share']);
      expect(share.ask.conditions[0].words).toMatch(/^Your share of the live budget is used up/);
      expect(share.ask.conditions[0].next).toMatch(/someone whose share is not spent/);
    });

    it('shadow mode: an approval is refused and an escalation reads Not sent, each saying how it changes', () => {
      const shadow = live({
        recovery: { ...RECOVERY, mode: 'shadow' },
        profile: profile({ recovery: { mode: 'shadow' } }),
      });
      const t = tasks(shadow);
      expect(t.approve.state).toBe('blocked');
      expect(codes(t.approve)).toEqual(['shadow']);
      expect(t.approve.conditions[0].next).toMatch(/set recovery\.mode to enabled in the site profile/);
      // A plan already waiting stays void once recovery is enabled, as after the stop
      expect(t.approve.conditions[0].next).toMatch(/A plan made before it needs fresh evidence\.$/);
      expect(t.approve.evidence[0].words).toBe('Recovery is in shadow mode, not stopped.');
      expect(t.escalate.state).toBe('limited');
      expect(codes(t.escalate)).toEqual(['mail_suppressed']);
      expect(t.escalate.conditions[0].next).toMatch(/notifications\.shadow_delivery/);
      // Someone who may not change the site is told who does
      expect(tasks({ ...shadow, can: { ...ALL, configure: false } }).approve.conditions[0].next).toMatch(
        /a person who may change the site's settings/,
      );
      // A site that lets email through in shadow mode sends it
      const mail = tasks({
        ...shadow,
        profile: profile({ recovery: { mode: 'shadow' }, notifications: { shadow_delivery: 'enabled' } }),
      });
      expect(mail.escalate.state).toBe('ready');
      expect(mail.escalate.evidence[0].words).toBe('The site profile lets email go out.');
    });

    it('insufficient role: each task names the resource it needs and who can do it instead', () => {
      const t = tasks(live({ can: NOTHING }));
      expect(t.read.state).toBe('ready');
      for (const id of ['scenario', 'ask', 'approve', 'escalate', 'close'] as const) {
        expect(t[id].state, id).toBe('blocked');
        expect(t[id].conditions[0].code, id).toBe('role');
        expect(t[id].conditions[0].words, id).toMatch(/needs the resource Shutter_\w+/);
        expect(t[id].conditions[0].next, id).toMatch(/^(Ask an? |Pick a suggested question)/);
      }
    });

    it('an operator: approving is for an approver, closing too where the site keeps the two-person rule', () => {
      const t = tasks(live({ can: OPERATOR }));
      expect(codes(t.approve)).toEqual(['role']);
      expect(t.approve.conditions[0].words).toMatch(/Shutter_Approve/);
      expect(t.close.state).toBe('ready');
      expect(t.close.evidence[0].words).toBe('The site profile lets an operator close.');
      const two = tasks(
        live({ can: OPERATOR, profile: profile({ approvers: { close_needs_approver: true } }) }),
      );
      expect(codes(two.close)).toEqual(['two_person']);
      expect(two.close.conditions[0].next).toBe('Ask an approver to close it. You can still escalate it.');
      // An approver closes whatever the rule says
      expect(
        tasks(live({ profile: profile({ approvers: { close_needs_approver: true } }) })).close.state,
      ).toBe('ready');
      // but, as the server's close, only with Shutter_Operate: a custom role that approves without it may not
      const approverOnly = tasks(live({ can: { ...NOTHING, approve: true } })).close;
      expect(codes(approverOnly)).toEqual(['role']);
      expect(approverOnly.conditions[0].words).toMatch(/Shutter_Operate/);
    });

    it("the public demo's own user: scenarios replay, and a question of their own is a judge's", () => {
      const t = tasks(live({ can: DEMO }));
      expect(t.scenario.state).toBe('limited');
      expect(t.scenario.conditions[0].words).toMatch(/^Your runs replay the recordings/);
      expect(codes(t.ask)).toEqual(['role']);
      expect(t.ask.conditions[0].words).toMatch(/Shutter_LiveAgents/);
      expect(t.ask.conditions[0].next).toMatch(/suggested question/);
    });
  });

  it('the stop: who stopped it and why, and who clears it', () => {
    const stopped = { ...RECOVERY, stopped: true, stoppedBy: 'approver', stopReason: 'receiver upgrade' };
    const t = tasks(live({ recovery: stopped }));
    expect(codes(t.approve)).toEqual(['stopped']);
    expect(t.approve.conditions[0].words).toBe(
      'Recovery is stopped by approver: receiver upgrade. No new recovery call is admitted.',
    );
    expect(t.approve.conditions[0].next).toMatch(/^Clear the stop under Stop Shutter recovery below/);
    expect(tasks(live({ recovery: stopped, can: DEMO })).approve.conditions[0].next).toMatch(
      /^A person who may both approve and change the site's settings clears it/,
    );
    // In shadow mode and stopped, both are said, the mode first: clearing the stop enables nothing
    const both = tasks(live({ recovery: { ...stopped, mode: 'shadow' } }));
    expect(codes(both.approve)).toEqual(['shadow', 'stopped']);
    expect(both.approve.evidence[0].words).toBe('Recovery is in shadow mode and stopped.');
  });

  it('a recovery control that cannot be read refuses every recovery call, and says so', () => {
    const t = tasks(live({ recovery: { ...RECOVERY, readable: false, stopped: true } }));
    expect(codes(t.approve)).toEqual(['control_unreadable']);
    expect(t.approve.evidence[0].words).toBe('The recovery control could not be read.');
  });

  it('scenarios on a site that is not a demo point to the trial', () => {
    const t = tasks(live({ settings: settings({ demo: false }) }));
    expect(t.scenario.state).toBe('blocked');
    expect(codes(t.scenario)).toEqual(['not_demo']);
    expect(t.scenario.conditions[0].next).toMatch(/trial/);
  });

  it('says "not known" for what was not read, never ready, and a role still blocks first', () => {
    const t = tasks(live({ settings: undefined, recovery: undefined, profile: undefined, can: OPERATOR }));
    expect(t.scenario.state).toBe('unknown');
    expect(t.ask.state).toBe('unknown');
    expect(t.escalate.state).toBe('unknown');
    expect(t.close.state).toBe('unknown');
    for (const id of ['scenario', 'ask', 'escalate', 'close'] as const)
      expect(t[id].conditions[0].next, id).toMatch(/^Reload the page/);
    expect(t.approve.state).toBe('blocked');
    expect(codes(t.approve)).toEqual(['role', 'not_read']);
    // An approver closes with or without the profile
    expect(tasks(live({ profile: undefined })).close.state).toBe('ready');
  });

  it('signed out, every task says to sign in', () => {
    for (const t of taskReadiness(live({ signedIn: false, can: NOTHING }))) {
      expect(t.state, t.id).toBe('blocked');
      expect(t.conditions[0], t.id).toMatchObject({ code: 'signed_out', next: 'Sign in.' });
    }
  });

  describe('in the trial', () => {
    const trial = (can: Can = ALL) =>
      tasks({
        trial: true,
        signedIn: true,
        can,
        settings: settings(),
        recovery: RECOVERY,
        profile: profile(),
      });

    it('everything is tried in this browser, and a question of your own needs a model the trial lacks', () => {
      const t = trial();
      for (const id of ['read', 'scenario', 'approve', 'escalate', 'close'] as const) {
        expect(t[id].state, id).toBe('ready');
        expect(t[id].does, id).toMatch(/this browser/);
        expect(t[id].evidence, id).toEqual([]);
      }
      expect(codes(t.ask)).toEqual(['trial_no_model']);
      expect(t.ask.conditions[0].next).toMatch(/pick a suggested question/);
    });

    it('never says "live" or "today" in its words', () => {
      for (const can of [ALL, OPERATOR, DEMO]) {
        const words = Object.values(trial(can))
          .flatMap((t) => [t.title, t.does, ...t.conditions.flatMap((c) => [c.words, c.next ?? ''])])
          .join(' ');
        expect(words).not.toMatch(/\blive\b/i);
        expect(words).not.toMatch(/\btoday\b/i);
      }
    });

    it("keeps the role's own reason beside the trial's", () => {
      expect(codes(trial(DEMO).ask)).toEqual(['trial_no_model', 'role']);
    });
  });

  it('every condition that stops a task carries a next step', () => {
    const inputs: ReadinessInput[] = [
      live({ can: NOTHING }),
      live({ can: OPERATOR, profile: profile({ approvers: { close_needs_approver: true } }) }),
      live({ settings: settings({ providerConfigured: false, demo: false }) }),
      live({ settings: settings({ providerConfigured: false, aiHubPresent: false }) }),
      live({ settings: settings({ mock: true }) }),
      live({ recovery: { ...RECOVERY, mode: 'shadow', stopped: true } }),
      live({ recovery: { ...RECOVERY, readable: false } }),
      live({ settings: undefined, recovery: undefined, profile: undefined }),
      live({ signedIn: false }),
    ];
    for (const i of inputs)
      for (const t of taskReadiness(i))
        for (const c of t.conditions.filter((x) => x.effect !== 'limits'))
          expect(c.next, `${t.id} ${c.code}`).toBeTruthy();
  });
});

describe('stateOf', () => {
  const c = (effect: 'blocks' | 'limits' | 'unknown') => ({ code: 'role' as const, effect, words: '' });
  it('blocks over not known over a limit over nothing', () => {
    expect(stateOf([])).toBe('ready');
    expect(stateOf([c('limits')])).toBe('limited');
    expect(stateOf([c('limits'), c('unknown')])).toBe('unknown');
    expect(stateOf([c('unknown'), c('blocks')])).toBe('blocked');
  });
});
