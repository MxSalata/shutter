import { Alert, Text } from '@mantine/core';
import { IconBroadcast } from '@tabler/icons-react';
import { useLiveStatus } from '@/api/hooks';
import type { LiveStatus } from '@/api/types';
import { formatAge, formatTime, parseTime, zoneLabel } from '@/lib/format';
import { useNow } from '@/lib/useNow';

/** "a new failure every 7 minutes", "every minute", or the unnumbered form when the server gave no interval. */
function cadence(every: number | undefined): string {
  if (!every || every < 1) return 'a new failure every few minutes';
  return every === 1 ? 'a new failure every minute' : `a new failure every ${every} minutes`;
}

/** "Last: S23a, the bed is occupied, 4 min ago.", or "" before the first story has played. */
function lastPlayed(live: LiveStatus, now: number): string {
  const last = live.last_played;
  if (!last?.scenario) return '';
  const age = formatAge(last.at, now);
  return `Last: ${[last.scenario, last.title, age].filter(Boolean).join(', ')}.`;
}

/** "Next: S8 at 14:12:00 BST.", or "" when no story is due or its time has passed (the player is behind or stopped). */
function nextDue(live: LiveStatus, now: number): string {
  const next = live.next;
  const at = parseTime(next?.at);
  if (!next?.scenario || !at || at.getTime() <= now) return '';
  return `Next: ${next.scenario} at ${formatTime(next.at)} ${zoneLabel(next.at)}.`;
}

/**
 * The live hospital's banner, on every page while `GET /settings` says `live.enabled`: how often a new failure
 * arrives, the story that played last and the one due next. Nothing is rendered for any other instance.
 */
export function LiveBanner() {
  const live = useLiveStatus();
  const now = useNow();
  if (!live) return null;
  const text = [lastPlayed(live, now), nextDue(live, now)].filter(Boolean).join(' ');
  return (
    <Alert
      // A region, not a status: the age changes every few seconds and a screen reader should not announce each change
      role="region"
      aria-label="Live hospital"
      color="blue"
      variant="light"
      icon={<IconBroadcast size={18} aria-hidden />}
      mb="md"
      py="xs"
      data-testid="live-banner"
    >
      <Text size="sm">
        Live hospital: {cadence(live.every_minutes)}.{text ? ` ${text}` : ''}
      </Text>
    </Alert>
  );
}
