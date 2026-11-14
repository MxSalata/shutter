import type { Budget, LiveAgents, Settings } from '@/api/types';
import { resetsHourly } from './budget';
import { isApiError } from './errors';
import { formatDay, formatTime, parseTime, zoneLabel } from './format';

/**
 * Where a visitor reads how to run Shutter with an API key of their own: the README's "Try it". One constant, so the
 * address changes in one place.
 */
export const INSTALL_URL = 'https://github.com/MxSalata/shutter#try-it';

/** The words of the notice that stay the same whatever the reason. */
export const STILL_WORKS = 'Open cases, recorded runs and the trial still work.';
export const INSTALL_LEAD = 'To run the live agents yourself, install Shutter with your own API key:';
export const INSTALL_LINK = 'how to install';

/**
 * Why live agent runs cannot go out now: `budget`, the instance's cap is spent; `share`, the signed-in user's own share
 * of it is (the cap may not be); `service`, the model provider refuses the key (`provider_auth`: the public demo's key
 * is switched off at a daily limit outside Shutter), or a reason the app does not know.
 */
export type LiveUnavailableReason = 'budget' | 'share' | 'service';

export interface LiveUnavailable {
  reason: LiveUnavailableReason;
  /**
   * Where the time comes from. `until`: the server's own (`live.agents.until`, or a refusal's `live.until`), "for now"
   * when it gives none. `reset`: a server without `live.agents`, worded from the budget, hourly on the public demo and
   * at 00:00 UTC elsewhere.
   */
  timing: 'until' | 'reset';
  /** An ISO UTC time: `live.agents.until`, or `budget.resetsAt` with the `reset` timing. */
  until: string | null;
  /** The public demo, which resets every hour (`resetsHourly`). */
  hourly: boolean;
  /** A demo instance (or the public demo): its words say "this demo" and offer the install link. */
  demo: boolean;
  /** What the server said, for Technical only: the field or the error code, and its sentence. */
  code: string;
  detail?: string;
}

const HOUR = 3_600_000;

/** The cap itself is reached: spend and reservations at or over a positive cap. */
const capReached = (b: Budget) =>
  b.dailyUsd > 0 && (b.spentTodayUsd ?? 0) + (b.reservedUsd ?? 0) >= b.dailyUsd;

/** The signed-in user's own share is spent, as the server says or by the figures. */
const shareSpent = (b: Budget) =>
  b.shareExhausted === true || (!!b.perUserUsd && b.perUserUsd > 0 && (b.spentByMeUsd ?? 0) >= b.perUserUsd);

/**
 * Whose budget is spent: the cap (the whole instance's) or only the signed-in user's share of it; null when neither.
 * The server marks `exhausted` when the user's share is spent too (Budget.StatusFor), so the share alone is told apart
 * by the cap's own figures.
 */
export function budgetLimit(b: Budget | undefined | null): 'budget' | 'share' | null {
  if (!b) return null;
  const share = shareSpent(b);
  if (share && !capReached(b)) return 'share';
  if (b.exhausted) return 'budget';
  return share ? 'share' : null;
}

function context(s: Settings | undefined) {
  const hourly = resetsHourly(s);
  return { hourly, demo: s?.demo === true || hourly };
}

/**
 * The reason as the app words it: `budget` stays, the share is read from the budget, anything else is the service. Since
 * 1.4.6 the budget also refuses a run whose estimate no longer fits what is left, while neither figure says spent: the
 * server's own sentence then tells the share ("Your share of the day's model budget ...") from the cap.
 */
function reasonOf(
  reason: string | null | undefined,
  b: Budget | undefined,
  detail?: string | null,
): LiveUnavailableReason {
  if (reason !== 'budget') return 'service';
  const limit = budgetLimit(b);
  if (limit) return limit;
  return /\byour share\b/i.test(detail ?? '') ? 'share' : 'budget';
}

/**
 * Whether live agent runs cannot go out now, and why, from `GET /settings`; null when they can, or when the server says
 * nothing about it. `live.agents` (v1.37) answers when the server sends it; otherwise the budget does: the cap, or the
 * signed-in user's share of it.
 */
export function liveUnavailable(s: Settings | undefined): LiveUnavailable | null {
  if (!s) return null;
  const agents: LiveAgents | undefined = s.live?.agents;
  if (agents) {
    if (agents.available !== false) return null;
    return {
      ...context(s),
      reason: reasonOf(agents.reason, s.budget, agents.detail),
      timing: 'until',
      until: agents.until ?? null,
      code: `live.agents.reason ${agents.reason ?? 'null'}`,
      detail: agents.detail || undefined,
    };
  }
  const limit = budgetLimit(s.budget);
  if (!limit) return null;
  return {
    ...context(s),
    reason: limit,
    timing: 'reset',
    until: s.budget?.resetsAt ?? null,
    code: limit === 'share' ? 'budget.shareExhausted' : 'budget.exhausted',
  };
}

/** A refusal's `live` object (v1.37), or the same fields at the top of an older body. */
function refusalLive(body: unknown): { reason?: string | null; until?: string | null } {
  if (!body || typeof body !== 'object') return {};
  const o = body as Record<string, unknown>;
  const live = o.live && typeof o.live === 'object' ? (o.live as Record<string, unknown>) : o;
  return {
    reason: typeof live.reason === 'string' ? live.reason : null,
    until: typeof live.until === 'string' ? live.until : null,
  };
}

/**
 * A live call the server refused because live agents cannot run: `409 live_unavailable` (v1.37, with `live`, the
 * availability object) or `409 budget_exhausted` (with the budget). Null for any other error.
 */
export function liveRefusal(error: unknown, s: Settings | undefined): LiveUnavailable | null {
  if (!isApiError(error) || error.status !== 409) return null;
  if (error.code !== 'live_unavailable' && error.code !== 'budget_exhausted') return null;
  const agents = s?.live?.agents;
  const body = (error.body ?? {}) as { budget?: Budget };
  const b = body.budget ?? s?.budget;
  const base = { ...context(s), code: `409 ${error.code}`, detail: error.detail || undefined };
  if (error.code === 'live_unavailable') {
    const live = refusalLive(error.body);
    const reason = live.reason ?? agents?.reason ?? null;
    return {
      ...base,
      reason: reasonOf(reason, b, error.detail),
      timing: 'until',
      until: live.until ?? (agents?.available === false ? (agents.until ?? null) : null),
    };
  }
  const limit = budgetLimit(b) ?? (/\bshare\b/i.test(error.detail) ? 'share' : 'budget');
  // With live.agents the server gives the time; without it the budget's reset words it
  if (agents)
    return {
      ...base,
      reason: limit,
      timing: 'until',
      until: agents.until ?? b?.resetsAt ?? null,
    };
  return { ...base, reason: limit, timing: 'reset', until: b?.resetsAt ?? null };
}

/** The provider refusing the key, as a run's error says it (what Shutter.Util.LiveAgents.IsAuthFailure reads, less a bare 401). */
const AUTH_FAILURE =
  /\bprovider_auth\b|\bauthentication\b|\bunauthori[sz]ed\b|\binvalid[ _-]?(x-)?api[ _-]?key\b|\bapi[ _-]?key\b[^.;]{0,40}\b(invalid|disabled|deactivated|revoked|expired)\b/i;

/**
 * A question that failed because live agents could not run, read from its error: the budget (`budget_exhausted`, the
 * cap or "Your share"), `live_unavailable`, or the provider refusing the key (`provider_auth`, an authentication error).
 * Null for any other failure.
 */
export function liveRefusalInText(
  text: string | null | undefined,
  s: Settings | undefined,
): LiveUnavailable | null {
  if (!text) return null;
  const agents = s?.live?.agents;
  const base = { ...context(s), code: 'failed', detail: text };
  const fromAgents = agents?.available === false ? (agents.until ?? null) : null;
  if (/\bbudget_exhausted\b|\bmodel budget\b.{0,80}?\bis spent\b/i.test(text)) {
    const reason: LiveUnavailableReason = /\byour share\b/i.test(text) ? 'share' : 'budget';
    if (agents) return { ...base, reason, timing: 'until', until: fromAgents ?? s?.budget?.resetsAt ?? null };
    return { ...base, reason, timing: 'reset', until: s?.budget?.resetsAt ?? null };
  }
  if (/\blive_unavailable\b/.test(text) || AUTH_FAILURE.test(text)) {
    const budget = /\blive_unavailable\b/.test(text) && agents?.reason === 'budget';
    return {
      ...base,
      reason: budget ? reasonOf('budget', s?.budget) : 'service',
      timing: 'until',
      until: fromAgents,
    };
  }
  return null;
}

/** "20:00 GMT", the app's time with its zone; with the day in front when it is a day or more away. */
function at(iso: string, now: number): string {
  const time = `${formatTime(iso).slice(0, 5)} ${zoneLabel(iso)}`;
  const d = parseTime(iso);
  return d && d.getTime() - now >= 24 * HOUR ? `${formatDay(iso, now)}, ${time}` : time;
}

/**
 * When live runs come back, in words. The public demo resets every hour, so on it the budget comes back at the next
 * reset: a time within the hour is that reset ("until 20:00 GMT, when the demo resets"); a later one (a server's next
 * 00:00 UTC, which the demo's reset comes before) is not said. A service outage keeps the server's time as it is.
 */
function when(u: LiveUnavailable, now: number): string {
  const d = parseTime(u.until);
  const ahead = d && d.getTime() > now ? d.getTime() - now : null;
  const budget = u.reason !== 'service';
  if (budget && u.hourly) {
    if (ahead !== null && ahead <= 1.1 * HOUR) return `until ${at(u.until!, now)}, when the demo resets`;
    return "until the demo's next reset, within the hour";
  }
  if (u.timing === 'reset') return 'until 00:00 UTC';
  return ahead !== null ? `until ${at(u.until!, now)}` : 'for now';
}

/**
 * The notice in words: what cannot run and until when, what still works and, on a demo, where to install Shutter with
 * one's own key. Plain words; the code and the server's sentence are for Technical (`code`, `detail`).
 */
export function liveUnavailableWords(
  u: LiveUnavailable,
  now: number = Date.now(),
): { lead: string; still: string; install: string | null } {
  const place = u.demo ? 'this demo' : 'this site';
  const until = when(u, now);
  const lead =
    u.reason === 'share'
      ? `Your share of the live budget is used up ${until}.`
      : u.reason === 'budget'
        ? `The live AI budget for ${place} is used up ${until}.`
        : `The live AI service for ${place} is unavailable ${until}.`;
  return { lead, still: STILL_WORKS, install: u.demo ? INSTALL_LEAD : null };
}
