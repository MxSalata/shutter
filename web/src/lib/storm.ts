import type { LiveStorm } from '@/api/types';
import { parseTime } from './format';

/**
 * "Break the feed" (CONTRACTS 4.4, v1.35): whether the live hospital's storm plays and whether its strip shows, which
 * the banner on every page and the settings' polling read. Small on purpose: it is in the entry chunk, while the strip,
 * the button and their words (features/storm) load only when a live banner draws them.
 */

/**
 * What a trial page's banner says instead of the button: the storm needs the demo hospital, which the trial has not. Not
 * "live demo": a trial page says "live" only in "live system" (DESIGN.md 1.3, N7; e2e/trial.spec.ts checks the banner).
 */
export const STORM_IN_TRIAL = 'Break the feed plays on the online demo.';

/** The states in which a storm has ended. */
const ENDED = new Set(['done', 'failed']);

/**
 * How long past its span a storm still marked as playing counts as playing. The player marks a storm done on its first
 * call after the span (every 5 s); one still playing a minute later was cut off, and the server ignores it too.
 */
const STALE_AFTER_MS = 60_000;

/** How long a storm that ended stays on the strip, from its end (or its start, for one that failed). */
export const STORM_SHOWN_FOR_MS = 10 * 60_000;

/** How often the settings are read while a storm plays, and otherwise while the live hospital is on. */
export const STORM_POLL_MS = 3_000;
export const LIVE_POLL_MS = 30_000;

/** The storm is playing: asked for and not yet done or failed, and not left behind by a player that stopped. */
export function isStormPlaying(storm: LiveStorm | null | undefined, now: number = Date.now()): boolean {
  if (!storm?.state || ENDED.has(storm.state)) return false;
  const ends = parseTime(storm.endsAt);
  return !ends || now < ends.getTime() + STALE_AFTER_MS;
}

/** The strip shows: while the storm plays, and for ten minutes after it ended. */
export function isStormShown(storm: LiveStorm | null | undefined, now: number = Date.now()): boolean {
  if (!storm?.state) return false;
  if (isStormPlaying(storm, now)) return true;
  if (!ENDED.has(storm.state)) return false;
  const end = parseTime(storm.endedAt) ?? parseTime(storm.startedAt);
  return !!end && now < end.getTime() + STORM_SHOWN_FOR_MS;
}
