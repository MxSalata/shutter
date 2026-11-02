import { Group, Stack, Text, Tooltip } from '@mantine/core';
import { IconBroadcast } from '@tabler/icons-react';
import { lazy, Suspense, useEffect, useRef, useState } from 'react';
import { useLocation } from 'react-router';
import { useCan, useLiveStatus, useSettings } from '@/api/hooks';
import type { LiveStatus } from '@/api/types';
import { TRIAL } from '@/env/mode';
import type { StormRefusal } from '@/features/storm/view';
import { budgetNoteLine } from '@/lib/budget';
import { formatAge, formatTime, parseTime, zoneLabel } from '@/lib/format';
import { liveUnavailable } from '@/lib/liveAgents';
import { isStormShown, STORM_IN_TRIAL } from '@/lib/storm';
import { useNow } from '@/lib/useNow';
import { HINT_EVENTS } from '@/theme';

/**
 * "Break the feed"'s button, notice and strip, in a chunk of their own: only a live banner draws them, so the entry stays
 * small for every other instance (e2e/trial.spec.ts holds the entry to its budget).
 */
const StormButton = lazy(() =>
  import('@/features/storm/BreakTheFeed').then((m) => ({ default: m.StormButton })),
);
const StormNotice = lazy(() =>
  import('@/features/storm/BreakTheFeed').then((m) => ({ default: m.StormNotice })),
);
const StormStrip = lazy(() => import('@/features/storm/StormStrip').then((m) => ({ default: m.StormStrip })));
/** The notice that the live agents cannot run, in its own chunk too: a banner draws it only at the cap or an outage. */
const LiveUnavailableNotice = lazy(() =>
  import('@/components/LiveUnavailableNotice').then((m) => ({ default: m.LiveUnavailableNotice })),
);

/** "a new failure every 7 minutes", "every minute", or the unnumbered form when the server gave no interval. */
function cadence(every: number | undefined): string {
  if (!every || every < 1) return 'a new failure every few minutes';
  return every === 1 ? 'a new failure every minute' : `a new failure every ${every} minutes`;
}

/** "Next: S8 at 14:12 BST.", or "" when no story is due or its time has passed (the player is behind or stopped). */
function nextDue(live: LiveStatus, now: number): string {
  const next = live.next;
  const at = parseTime(next?.at);
  if (!next?.scenario || !at || at.getTime() <= now) return '';
  return `Next: ${next.scenario} at ${formatTime(next.at).slice(0, 5)} ${zoneLabel(next.at)}.`;
}

/** A soft pulse of the dot, three times, whenever a new story has played (none under reduced motion). */
function usePulse(at: string | undefined): number {
  const [pulse, setPulse] = useState(0);
  const seen = useRef(at);
  useEffect(() => {
    if (at && seen.current && at !== seen.current) setPulse((n) => n + 1);
    seen.current = at;
  }, [at]);
  return pulse;
}

/**
 * The hospital feed's banner, on every page while `GET /settings` says `live.enabled` (the public demo's live
 * hospital): how often a new failure arrives, the story that played last (its title on hover or focus) and the one due
 * next. A neutral band with a broadcast mark, never an information tone. In a trial page it is the recorded feed
 * replayed, and says so: "Hospital feed (replayed)", so the trial never says "live" of itself. Nothing is rendered
 * for any other instance.
 *
 * "Break the feed" (after-restyle B7): for a user who operates, a live banner offers the storm (StormButton), and
 * while one plays or has just finished it carries the storm's strip, on every page but Incidents, which shows the strip
 * in its own place (so it is neither drawn nor announced twice). A refusal stands under the line as a calm notice. A
 * trial page has no demo hospital to break: its banner says where the storm plays instead.
 *
 * The live budget: a short line under the feed's, figure first, says what the author pays for the live agents
 * (`budgetNoteLine`), and while the live agents cannot run (the budget used up, the provider refusing the key) the
 * notice under it says so plainly, until when, and where to install Shutter with one's own key. Neither is in the trial.
 */
export function LiveBanner() {
  const live = useLiveStatus();
  const now = useNow();
  const pulse = usePulse(live?.last_played?.at);
  const can = useCan();
  const { pathname } = useLocation();
  const [refusal, setRefusal] = useState<StormRefusal | null>(null);
  const settings = useSettings().data;
  if (!live) return null;
  const note = TRIAL ? null : budgetNoteLine(settings);
  const unavailable = TRIAL ? null : liveUnavailable(settings);
  const name = TRIAL ? 'Hospital feed (replayed)' : 'Live hospital';
  const last = live.last_played;
  const next = nextDue(live, now);
  const storm = !TRIAL && live.storm && isStormShown(live.storm, now) ? live.storm : null;
  const action = TRIAL ? (
    <Text size="sm" data-testid="storm-in-trial">
      {STORM_IN_TRIAL}
    </Text>
  ) : can.operate ? (
    <Suspense fallback={null}>
      <StormButton onRefused={setRefusal} />
    </Suspense>
  ) : null;
  return (
    <div
      // A region, not a status: the age changes every few seconds and a screen reader should not announce each change
      role="region"
      aria-label={name}
      className="live-banner"
      data-testid="live-banner"
    >
      <Group gap="xs" wrap="wrap" justify="space-between" align="flex-start">
        <Group gap="xs" wrap="nowrap" align="flex-start" style={{ minWidth: 0, flex: '1 1 20rem' }}>
          <IconBroadcast size={18} aria-hidden style={{ flex: 'none', marginTop: 2 }} />
          <span className="live-dot" aria-hidden key={pulse} data-pulse={pulse > 0 || undefined} />
          <Stack gap={0} style={{ minWidth: 0, flex: '1 1 auto' }}>
            <Text size="sm" data-testid="live-line">
              {name}: {cadence(live.every_minutes)}.
              {last?.scenario ? (
                <>
                  {' '}
                  Last:{' '}
                  {last.title ? (
                    <Tooltip label={last.title} withArrow events={HINT_EVENTS}>
                      <span className="live-story" tabIndex={0}>
                        {last.scenario}
                      </span>
                    </Tooltip>
                  ) : (
                    last.scenario
                  )}
                  {last.at ? `, ${formatAge(last.at, now)}` : ''}.
                </>
              ) : null}
              {next ? ` ${next}` : ''}
            </Text>
            {note ? (
              <Text size="xs" className="live-budget-line" data-testid="live-budget-line">
                {note}
              </Text>
            ) : null}
          </Stack>
        </Group>
        {action}
      </Group>
      <Suspense fallback={null}>
        {unavailable ? <LiveUnavailableNotice state={unavailable} className="live-unavailable" /> : null}
        {refusal && !TRIAL ? <StormNotice refusal={refusal} onClose={() => setRefusal(null)} /> : null}
        {storm && pathname !== '/incidents' ? <StormStrip storm={storm} /> : null}
      </Suspense>
    </div>
  );
}
