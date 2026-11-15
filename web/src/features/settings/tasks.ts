import type { Can, RecoveryControl, Settings, SiteProfile } from '@/api/types';
import { mailOutcome } from '@/features/cases/case/escalationWords';
import { liveUnavailable, liveUnavailableWords } from '@/lib/liveAgents';
import { plural } from '@/lib/format';
import { answeringOf } from './settingsText';

/**
 * Whether each task a person may come to do is ready for them here, now, and if not what stands in the way and what to do
 * next: read only, from what the app already reads (GET /me's `can`, GET /settings, GET /recovery-control, the site
 * profile, GET /health's `last_live_run`, GET /costs). The pages keep their own checks and decide as before when a button is pressed; this says the same
 * facts together, before the press. Pure, so a table test holds every state.
 */

export type TaskId = 'read' | 'scenario' | 'ask' | 'approve' | 'escalate' | 'close';

/** `limited`: it can be done, with a consequence said; `unknown`: what it depends on was not read. */
export type TaskState = 'ready' | 'limited' | 'blocked' | 'unknown';

export type ConditionCode =
  | 'signed_out'
  | 'role'
  | 'trial_no_model'
  | 'not_demo'
  | 'replays_only'
  | 'replay_edition'
  | 'no_key'
  | 'mimic'
  | 'budget'
  | 'share'
  | 'provider'
  | 'control_unreadable'
  | 'shadow'
  | 'stopped'
  | 'mail_suppressed'
  | 'two_person'
  | 'not_read';

/** What stands in the way of a task, or limits it: its words and the next useful action. */
export interface Condition {
  code: ConditionCode;
  effect: 'blocks' | 'limits' | 'unknown';
  words: string;
  next?: string;
}

/**
 * A fact the readiness rests on, kept apart by kind (the review's U145-04): `set up`, what the installation is configured
 * to do; `now`, what holds at the moment the page read it (`at`, an ISO UTC time); `seen`, what the store shows happened,
 * with `started`, the ISO UTC time the run it names started, where it names one, and `code`, that run's status as the
 * store keeps it, said on Technical only.
 */
export interface Evidence {
  kind: 'set up' | 'now' | 'seen';
  words: string;
  at?: string;
  started?: string;
  code?: string;
}

export interface TaskReadiness {
  id: TaskId;
  title: string;
  state: TaskState;
  /** What the task does here when nothing stands in the way. */
  does: string;
  /** In the order a person clears them: who they are first, then what the site set, then what passes by itself. */
  conditions: Condition[];
  evidence: Evidence[];
}

export interface ReadinessInput {
  /** The trial: recorded cases answered in this browser. */
  trial: boolean;
  signedIn: boolean;
  can: Can;
  /** GET /settings, and when the page read it; undefined when it was not read. */
  settings?: Settings;
  settingsAt?: string;
  recovery?: RecoveryControl;
  recoveryAt?: string;
  profile?: SiteProfile;
  profileAt?: string;
  /** GET /costs `totals.liveRuns`: the board's runs that reached a real model, all time. */
  liveRuns?: number;
  /**
   * GET /health `last_live_run`: the newest run for a real model (live or record, never the API mimic), null when none
   * has; undefined when it was not read or has not answered yet. When read it is said instead of the count, which leaves
   * out reviews' runs.
   */
  lastLive?: { at: string; status: string } | null;
  now?: number;
}

/** The state a task's conditions give: anything that blocks, then anything not known, then any limit. */
export function stateOf(conditions: readonly Condition[]): TaskState {
  if (conditions.some((c) => c.effect === 'blocks')) return 'blocked';
  if (conditions.some((c) => c.effect === 'unknown')) return 'unknown';
  if (conditions.some((c) => c.effect === 'limits')) return 'limited';
  return 'ready';
}

const SIGNED_OUT: Condition = {
  code: 'signed_out',
  effect: 'blocks',
  words: 'Nobody is signed in.',
  next: 'Sign in.',
};

const role = (words: string, next: string): Condition => ({ code: 'role', effect: 'blocks', words, next });

const notRead = (what: string, words: string, next: string): Condition => ({
  code: 'not_read',
  effect: 'unknown',
  words: `${what} could not be read, so ${words}`,
  next,
});

const SETTINGS_NOT_READ = (words: string) =>
  notRead('The settings', words, 'Reload the page. The task checks it again when you press.');

function task(
  id: TaskId,
  title: string,
  does: string,
  conditions: Condition[],
  evidence: Evidence[] = [],
): TaskReadiness {
  return { id, title, state: stateOf(conditions), does, conditions, evidence };
}

// ---- the tasks ----

function read(i: ReadinessInput): TaskReadiness {
  return task(
    'read',
    'Read cases and recorded runs',
    i.trial
      ? "The recorded cases, their evidence and the agents' runs, in this browser."
      : "Any case, its evidence and the agents' runs, recorded or not.",
    i.signedIn ? [] : [SIGNED_OUT],
  );
}

/** How a scenario's agents answer for this user here: from recordings, against the mimic, or on a model. */
function scenarioAnswering(i: ReadinessInput, s: Settings): Condition | Evidence {
  if (!i.can.liveAgents)
    return {
      code: 'replays_only',
      effect: 'limits',
      words:
        'Your runs replay the recordings: no model is called and nothing is spent. The single investigator, never recorded, cannot be played.',
    };
  if (!s.providerConfigured && !s.mock)
    return {
      code: 'replays_only',
      effect: 'limits',
      words: 'No model key is configured here, so the runs replay the recordings and spend nothing.',
    };
  const kind = answeringOf(s).kind;
  return {
    kind: 'set up',
    words:
      kind === 'replay'
        ? 'Its agents replay the recordings: nothing is spent.'
        : kind === 'mimic'
          ? 'Its agents run against the API mimic, a test fixture: no model is called.'
          : kind === 'live' || kind === 'record'
            ? "Its agents call the model, and their runs count against your share of the day's budget."
            : 'Its agents answer as the Agents section shows, item by item.',
  };
}

function scenario(i: ReadinessInput): TaskReadiness {
  const title = 'Run a scenario';
  const does = i.trial
    ? 'Plays it in this browser from the recordings: nothing is sent to IRIS.'
    : "Plays it through the demo hospital's feed, one run at a time.";
  const conditions: Condition[] = [];
  if (!i.signedIn) conditions.push(SIGNED_OUT);
  else if (!i.can.scenarios)
    conditions.push(
      role(
        'Running a scenario needs the resource Shutter_Scenarios, which your sign-in does not hold.',
        'Ask an operator or an approver to run it. Its recorded cases can still be read.',
      ),
    );
  if (i.trial) return task('scenario', title, does, conditions);
  const s = i.settings;
  if (!s)
    return task('scenario', title, does, [
      ...conditions,
      SETTINGS_NOT_READ('whether this is a demo is not known.'),
    ]);
  if (!s.demo)
    conditions.push({
      code: 'not_demo',
      effect: 'blocks',
      words: "Scenarios play only on a demo installation, and this one is a site's.",
      next: 'Play them in the trial instead: Help, Open the trial environment.',
    });
  const answering = scenarioAnswering(i, s);
  if ('effect' in answering) return task('scenario', title, does, [...conditions, answering]);
  return task('scenario', title, does, conditions, [{ ...answering, at: i.settingsAt }]);
}

/** What the next step is when the model cannot be asked now, by the reason. */
function unavailableNext(reason: 'budget' | 'share' | 'service', demo: boolean): string {
  const recorded = 'A suggested question on a case still answers from its recording.';
  if (reason === 'share') return `Wait for the reset, or ask someone whose share is not spent. ${recorded}`;
  if (reason === 'budget')
    return demo
      ? `Wait for the reset. ${recorded}`
      : `Wait for the reset, or the person who runs the site raises SHUTTER_DAILY_BUDGET_USD. ${recorded}`;
  return demo
    ? 'Try again later. To ask your own now, install Shutter with your own API key.'
    : 'Try again later. If it lasts, an administrator checks the model key with the provider and sets a new one.';
}

function ask(i: ReadinessInput): TaskReadiness {
  const title = 'Ask the agents a question of your own';
  const does = "The agents answer it on the model from the case's evidence; nothing is written to the case.";
  const conditions: Condition[] = [];
  if (i.trial)
    conditions.push({
      code: 'trial_no_model',
      effect: 'blocks',
      words: 'The trial has no model: every answer here is a recording.',
      next: 'Open a case and pick a suggested question: its answers were recorded with the real agents. To ask your own, install Shutter with your own API key.',
    });
  if (!i.signedIn) conditions.push(SIGNED_OUT);
  else if (!i.can.operate)
    conditions.push(
      role(
        'Asking needs the resource Shutter_Operate, which your sign-in does not hold.',
        'Ask an operator or an approver to ask it.',
      ),
    );
  else if (!i.can.liveAgents)
    conditions.push(
      role(
        "A question of your own runs the agents on the model and spends the day's budget, which needs the resource Shutter_LiveAgents; your sign-in does not hold it.",
        'Pick a suggested question on a case: its answers were recorded with the real agents.',
      ),
    );
  if (i.trial) return task('ask', title, does, conditions);
  const s = i.settings;
  if (!s)
    return task('ask', title, does, [
      ...conditions,
      SETTINGS_NOT_READ('whether a model can be asked is not known.'),
    ]);
  const evidence: Evidence[] = [
    {
      kind: 'set up',
      words: s.mock
        ? 'The API mimic is on, a test fixture: no model is called.'
        : s.providerConfigured
          ? 'A model key is configured.'
          : 'No model key is configured.',
    },
  ];
  if (s.mock)
    // As the Ask panel does: the mimic answers the agents' runs, but a question of your own needs a model
    conditions.push({
      code: 'mimic',
      effect: 'blocks',
      words:
        'The API mimic answers here, a test fixture: the Ask panel takes no question of your own while it is on.',
      next: 'Pick a suggested question on a case: its answers were recorded with the real agents. To ask your own, an administrator switches the mimic off (Shutter.Mock.Setup_Disable) and sets a model key.',
    });
  else if (!s.providerConfigured)
    conditions.push(
      s.aiHubPresent === false
        ? {
            code: 'replay_edition',
            effect: 'blocks',
            words: 'This is the replay edition: it has no AI Hub, so its agents only replay recordings.',
            next: 'Your own questions need the AI Hub edition with a model key (switch editions: running.md). A suggested question still answers from its recording.',
          }
        : {
            code: 'no_key',
            effect: 'blocks',
            words: 'No model key is configured here, so the agents only replay recordings.',
            next: 'An administrator sets ANTHROPIC_API_KEY (or OPENAI_API_KEY) in .env and starts the production again: it configures the provider at its start. A suggested question still answers from its recording.',
          },
    );
  else {
    const u = liveUnavailable(s);
    if (u) {
      const code: ConditionCode = u.reason === 'service' ? 'provider' : u.reason;
      conditions.push({
        code,
        effect: 'blocks',
        words: liveUnavailableWords(u, i.now).lead,
        next: unavailableNext(u.reason, u.demo),
      });
      evidence.push({ kind: 'now', words: 'The model cannot be asked.', at: i.settingsAt });
    } else evidence.push({ kind: 'now', words: 'The model can be asked.', at: i.settingsAt });
  }
  if (i.lastLive) evidence.push(lastLiveSeen(i.lastLive));
  // Health not read, or not answered yet: the board's count, which the costs give
  else if (i.lastLive === null || typeof i.liveRuns === 'number')
    evidence.push({
      kind: 'seen',
      words:
        i.lastLive !== null && i.liveRuns
          ? `${plural(i.liveRuns, 'agent run')} reached a real model on this instance.`
          : 'No agent run has reached a real model on this instance yet.',
    });
  return task('ask', title, does, conditions, evidence);
}

/**
 * Why a run was stopped before any call to the model, by the status the Agent operation stores for it: the day's budget
 * or the requester's share of it spent (`budget_exhausted`), the budget not checked in time (`budget_busy`), the provider
 * refusing the key (`provider_auth`). Such a run is kept with the item's mode and model, so the health report can name it.
 */
const REFUSED_BEFORE_CALL: Record<string, string> = {
  budget_exhausted: "the day's live AI budget, or its requester's share of it, was used up",
  budget_busy: 'the budget could not be checked in time',
  provider_auth: 'the model provider refused the key',
};

/** The health report's newest run, in words: answered, refused before any call, or ended without a usable answer. */
function lastLiveSeen(run: { at: string; status: string }): Evidence {
  if (run.status === 'ok')
    return { kind: 'seen', words: 'The newest run that reached a real model answered.', started: run.at };
  const why = Object.hasOwn(REFUSED_BEFORE_CALL, run.status) ? REFUSED_BEFORE_CALL[run.status] : undefined;
  return {
    kind: 'seen',
    words: why
      ? `The newest run meant for a real model was refused before any call to it: ${why}.`
      : 'The newest run that reached a real model ended without a usable answer.',
    started: run.at,
    code: run.status,
  };
}

function approve(i: ReadinessInput): TaskReadiness {
  const title = "Approve a recovery or an incident's release";
  const does = i.trial
    ? 'Tried in this browser: approving replays the recorded outcome, and nothing is sent.'
    : "Lets a reviewed plan, or an incident's release, write to the receiver after the gate.";
  const conditions: Condition[] = [];
  if (!i.signedIn) conditions.push(SIGNED_OUT);
  else if (!i.can.approve)
    conditions.push(
      role(
        'Approving needs the resource Shutter_Approve, which your sign-in does not hold.',
        'Ask an approver. You can still read the plan, its gate and its evidence.',
      ),
    );
  if (i.trial) return task('approve', title, does, conditions);
  const c = i.recovery;
  if (!c)
    return task('approve', title, does, [
      ...conditions,
      notRead(
        'The recovery control',
        'whether recovery is on is not known.',
        'Reload the page. An approval checks it again when you press.',
      ),
    ]);
  const mayClear = i.can.configure && i.can.approve;
  if (!c.readable)
    conditions.push({
      code: 'control_unreadable',
      effect: 'blocks',
      words: 'Shutter cannot read its recovery control, so it refuses every recovery call.',
      next: 'An administrator reads the Event Log. Nothing is sent until the control reads again.',
    });
  else {
    if (c.mode !== 'enabled')
      conditions.push({
        code: 'shadow',
        effect: 'blocks',
        words:
          'Shutter is in shadow mode: it investigates and records what it would propose, refuses an approval, and rehearses and sends nothing.',
        next: i.can.configure
          ? "Enabling recovery is the site's decision. Once it is made, set recovery.mode to enabled in the site profile. A plan made before it needs fresh evidence."
          : "Enabling recovery is the site's decision: a person who may change the site's settings sets recovery.mode to enabled in the site profile. A plan made before it needs fresh evidence.",
      });
    if (c.stopped)
      conditions.push({
        code: 'stopped',
        effect: 'blocks',
        words: `Recovery is stopped${c.stoppedBy ? ` by ${c.stoppedBy}` : ''}${c.stopReason ? `: ${c.stopReason}` : ''}. No new recovery call is admitted.`,
        next: mayClear
          ? 'Clear the stop under Stop Shutter recovery below, with a reason. A plan made before it needs fresh evidence.'
          : "A person who may both approve and change the site's settings clears it. A plan made before it needs fresh evidence.",
      });
  }
  const control = !c.readable
    ? 'The recovery control could not be read.'
    : `Recovery ${c.mode === 'enabled' ? 'is enabled' : 'is in shadow mode'}${c.stopped ? ' and stopped' : ', not stopped'}.`;
  return task('approve', title, does, conditions, [{ kind: 'now', words: control, at: i.recoveryAt }]);
}

function escalate(i: ReadinessInput): TaskReadiness {
  const title = 'Escalate a case by email';
  const does = i.trial
    ? 'Tried in this browser: nobody is emailed.'
    : 'Emails the team the site names, or saves an email file when no mail server is set.';
  const conditions: Condition[] = [];
  if (!i.signedIn) conditions.push(SIGNED_OUT);
  else if (!i.can.operate)
    conditions.push(
      role(
        'Escalating needs the resource Shutter_Operate, which your sign-in does not hold.',
        'Ask an operator or an approver to escalate it.',
      ),
    );
  if (i.trial) return task('escalate', title, does, conditions);
  const outcome = mailOutcome(i.profile);
  if (outcome === 'unknown')
    return task('escalate', title, does, [
      ...conditions,
      notRead(
        'The site profile',
        'whether an email goes out is not known.',
        'Reload the page. The escalation dialog says it again before you send.',
      ),
    ]);
  if (outcome === 'suppressed')
    conditions.push({
      code: 'mail_suppressed',
      effect: 'limits',
      words:
        'Shutter is in shadow mode, so an escalation is recorded and reads Not sent: nobody is emailed and no email file is saved.',
      next: 'To send it, the site enables recovery, or allows email in shadow mode (notifications.shadow_delivery in the site profile), and someone sends it again.',
    });
  return task('escalate', title, does, conditions, [
    {
      kind: 'set up',
      words:
        outcome === 'mail' ? 'The site profile lets email go out.' : 'The site profile holds email back.',
      at: i.profileAt,
    },
  ]);
}

function close(i: ReadinessInput): TaskReadiness {
  const title = 'Close a case handled by hand';
  const does = i.trial
    ? 'Tried in this browser, with your reason.'
    : 'Closes an escalated, blocked or failed case the team corrected by hand, with your reason.';
  if (!i.signedIn) return task('close', title, does, [SIGNED_OUT]);
  // The server's close needs Shutter_Operate whoever asks, as the case's own action checks it first
  if (!i.can.operate)
    return task('close', title, does, [
      role(
        'Closing needs the resource Shutter_Operate, which your sign-in does not hold.',
        'Ask an operator or an approver to close it.',
      ),
    ]);
  // An approver closes whatever the site's rule says
  if (i.can.approve) return task('close', title, does, []);
  if (!i.profile)
    return task('close', title, does, [
      notRead(
        'The site profile',
        'whether this site keeps the two-person rule is not known.',
        'Reload the page. Close checks it again when you press.',
      ),
    ]);
  if (i.profile.approvers?.close_needs_approver === true)
    return task(
      'close',
      title,
      does,
      [
        {
          code: 'two_person',
          effect: 'blocks',
          words:
            'This site keeps the two-person rule: an approver closes a case handled by hand (approvers.close_needs_approver).',
          next: 'Ask an approver to close it. You can still escalate it.',
        },
      ],
      [{ kind: 'set up', words: 'The site profile asks for an approver to close.', at: i.profileAt }],
    );
  return task(
    'close',
    title,
    does,
    [],
    [{ kind: 'set up', words: 'The site profile lets an operator close.', at: i.profileAt }],
  );
}

/** Every task, in the order a person meets them: read, try, ask, decide, hand on, close. */
export function taskReadiness(i: ReadinessInput): TaskReadiness[] {
  return [read(i), scenario(i), ask(i), approve(i), escalate(i), close(i)];
}

/** The state's badge: its words and its tone. */
export const STATE_BADGES: Record<
  TaskState,
  { label: string; tone: 'positive' | 'info' | 'attention' | 'neutral' }
> = {
  ready: { label: 'Ready', tone: 'positive' },
  limited: { label: 'Ready, with a limit', tone: 'info' },
  blocked: { label: 'Not now', tone: 'attention' },
  unknown: { label: 'Not known', tone: 'neutral' },
};

/** Each task in a word or two, for the section's one line. */
const SHORT: Record<TaskId, string> = {
  read: 'reading',
  scenario: 'scenarios',
  ask: 'your own questions',
  approve: 'approving',
  escalate: 'escalating',
  close: 'closing',
};

/**
 * The section's one line: how many tasks are ready for the reader (with a limit or not), then the ones that are not now
 * and the ones not known, by their short names: "5 of 6 ready for you. Not now: your own questions".
 */
export function summaryLine(tasks: readonly TaskReadiness[]): string {
  const ready = tasks.filter((t) => t.state === 'ready' || t.state === 'limited').length;
  const named = (state: TaskState) =>
    tasks
      .filter((t) => t.state === state)
      .map((t) => SHORT[t.id])
      .join(', ');
  const parts = [
    ready === tasks.length
      ? `All ${tasks.length} ready for you`
      : `${ready} of ${tasks.length} ready for you`,
  ];
  if (named('blocked')) parts.push(`Not now: ${named('blocked')}`);
  if (named('unknown')) parts.push(`Not known: ${named('unknown')}`);
  return parts.join('. ');
}
