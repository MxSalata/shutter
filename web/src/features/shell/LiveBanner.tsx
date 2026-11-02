import { Group, Text, Tooltip } from '@mantine/core';
import { IconBroadcast } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';
import { useLiveStatus } from '@/api/hooks';
import type { LiveStatus } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { formatAge, formatTime, parseTime, zoneLabel } from '@/lib/format';
import { useNow } from '@/lib/useNow';
import { HINT_EVENTS } from '@/theme';

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
 */
export function LiveBanner() {
  const live = useLiveStatus();
  const now = useNow();
  const pulse = usePulse(live?.last_played?.at);
  if (!live) return null;
  const name = TRIAL ? 'Hospital feed (replayed)' : 'Live hospital';
  const last = live.last_played;
  const next = nextDue(live, now);
  return (
    <div
      // A region, not a status: the age changes every few seconds and a screen reader should not announce each change
      role="region"
      aria-label={name}
      className="live-banner"
      data-testid="live-banner"
    >
      <Group gap="xs" wrap="nowrap" align="flex-start">
        <IconBroadcast size={18} aria-hidden style={{ flex: 'none', marginTop: 2 }} />
        <span className="live-dot" aria-hidden key={pulse} data-pulse={pulse > 0 || undefined} />
        <Text size="sm">
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
      </Group>
    </div>
  );
}
