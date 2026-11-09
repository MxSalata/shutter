import { Anchor, Text, Tooltip, VisuallyHidden } from '@mantine/core';
import { IconBroadcast } from '@tabler/icons-react';
import { lazy, Suspense, useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router';
import { useCan, useCasesOnce, useLiveStatus, useSettings } from '@/api/hooks';
import type { LiveStatus } from '@/api/types';
import { TRIAL, trialHref } from '@/env/mode';
import type { StormRefusal } from '@/features/storm/view';
import { budgetNoteLine, resetsHourly } from '@/lib/budget';
import { formatAge, formatTime, parseTime, zoneLabel } from '@/lib/format';
import { HOSPITAL_NAME, TRIAL_BOARD_CASE } from '@/lib/hospital';
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

/** The story due next and its clock ("S8", "14:12 BST"), or null when none is due or its time has passed (the player is behind or stopped). */
function nextDue(live: LiveStatus, now: number): { scenario: string; clock: string; at: number } | null {
  const next = live.next;
  const at = parseTime(next?.at);
  if (!next?.scenario || !at || at.getTime() <= now) return null;
  return {
    scenario: next.scenario,
    clock: `${formatTime(next.at).slice(0, 5)} ${zoneLabel(next.at)}`,
    at: at.getTime(),
  };
}

/** How far the feed has gone from the last story towards the next, 0 to 1, for the timeline's track; null without both. */
function progress(lastAt: string | undefined, nextAt: number | undefined, now: number): number | null {
  const from = parseTime(lastAt)?.getTime();
  if (from === undefined || nextAt === undefined || nextAt <= from) return null;
  return Math.min(1, Math.max(0, (now - from) / (nextAt - from)));
}

/** Words a screen reader and the line's tests read, which the bar shows by its layout instead (a colon, a comma). */
const said = (words: string) => <VisuallyHidden component="span">{words}</VisuallyHidden>;

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
 * hospital), as a bar in two parts. On the left, what it is: "Live demo hospital" with the hospital's name and how often
 * a new failure arrives beneath it in small type. In the centre, a timeline: the story that played last (its title on
 * hover or focus) and the one due next as two points on a track, filled as far as the feed has gone between them, and
 * left open (dashed) where no time is promised. On the right, "Break the feed". Under the bar, the notes on the budget,
 * the hourly reset and the board, in one line of small text with a rule between each.
 *
 * The bar's line (`live-line`) still reads as one sentence to a screen reader and the tests: "Mikolaj's Fictional
 * Hospital, live: a new failure every 7 minutes. Last: S23a, 59 s ago. Next: S3 at 18:35 GMT."; the punctuation the
 * layout shows by position is visually hidden. The label over it ("Live demo hospital") says the same and is hidden
 * from assistive technology.
 *
 * Live, the bar is a strong band: the card surface, a 4 px edge in the text colour, a solid mark, and a dot on the last
 * story that pulses three times whenever a new story has played (none under reduced motion). In a trial page it is the
 * recorded feed replayed, and says so: "Mikolaj's Fictional Hospital, replayed" and "Hospital feed, replayed" over it,
 * in a calmer band (the page tone, a dashed edge, a muted mark), so the trial never says "live" of itself. Nothing is
 * rendered for any other instance.
 *
 * "Break the feed" (after-restyle B7): for a user who operates, a live banner offers the storm (StormButton), and
 * while one plays or has just finished it carries the storm's strip, on every page but Incidents, which shows the strip
 * in its own place (so it is neither drawn nor announced twice). A refusal stands under the bar as a calm notice. A
 * trial page has no demo hospital to break: its banner says where the storm plays instead.
 *
 * The live budget: a short note, figure first, says what the author pays for the live agents (`budgetNoteLine`), and
 * while the live agents cannot run (the budget used up, the provider refusing the key) the notice under the notes says
 * so plainly, until when, and where to install Shutter with one's own key. Neither is in the trial.
 *
 * The hourly reset: the public demo goes back to its frozen image on the hour, so a note says so. A trial page never
 * resets (its recording answers `live.enabled` too), so it never shows it.
 */
export function LiveBanner() {
  const live = useLiveStatus();
  const now = useNow();
  const pulse = usePulse(live?.last_played?.at);
  const can = useCan();
  const { pathname } = useLocation();
  const [refusal, setRefusal] = useState<StormRefusal | null>(null);
  const settings = useSettings().data;
  // Only for the note below, which only a live banner's visitor without the live agents reads
  const noBoard = !!live && !TRIAL && !can.liveAgents;
  const s8Cases = useCasesOnce({ scenario: 'S8', limit: 100 }, noBoard).data?.items;
  const boardCase = s8Cases?.find((c) => c.scenario === 'S8');
  if (!live) return null;
  const note = TRIAL ? null : budgetNoteLine(settings);
  const unavailable = TRIAL ? null : liveUnavailable(settings);
  const feed = TRIAL ? 'replayed' : 'live';
  const name = `${HOSPITAL_NAME}, ${feed}`;
  const last = live.last_played?.scenario ? live.last_played : null;
  const next = nextDue(live, now);
  const done = last ? progress(last.at ?? undefined, next?.at, now) : null;
  const storm = !TRIAL && live.storm && isStormShown(live.storm, now) ? live.storm : null;
  const action = TRIAL ? (
    <Text size="sm" className="live-action-words" data-testid="storm-in-trial">
      {STORM_IN_TRIAL}
    </Text>
  ) : can.operate ? (
    <Suspense fallback={null}>
      <StormButton onRefused={setRefusal} />
    </Suspense>
  ) : null;
  const resets = !TRIAL && resetsHourly(settings);
  const boardNote =
    noBoard && boardCase ? (
      // The hospital's rotation is settled by its policy, but the instance's S8 case went to the real board, and its
      // page shows it: saying "no agent" over that case would be wrong
      <Text size="xs" data-testid="live-board-link">
        Most of this hospital&apos;s failures are settled by its written policy, with no agent. One went to
        the live board:{' '}
        <Anchor
          component={Link}
          to={`/cases/${encodeURIComponent(boardCase.caseId)}`}
          size="xs"
          underline="always"
        >
          {boardCase.caseId}
        </Anchor>
      </Text>
    ) : noBoard && s8Cases ? (
      // Only once the instance has answered with no such case, so the note never says "no agent" over one that is
      // still loading: a visitor without the live agents then sees the board decide in the trial's recording of S8,
      // at no cost
      <Text size="xs" data-testid="live-board-link">
        The hospital&apos;s own failures are settled by its written policy, with no agent.{' '}
        <Anchor href={trialHref(`#/cases/${TRIAL_BOARD_CASE}`)} size="xs" underline="always">
          See the board decide: S8 in the trial
        </Anchor>
      </Text>
    ) : null;
  return (
    <div
      // A region, not a status: the age changes every few seconds and a screen reader should not announce each change
      role="region"
      aria-label={name}
      className="live-banner"
      data-feed={feed}
      data-testid="live-banner"
    >
      <div className="live-bar">
        {/* What the bar is, said again by the line's own words, so hidden from assistive technology */}
        <div className="live-kicker" aria-hidden>
          <span className="live-mark">
            <IconBroadcast size={14} stroke={2} />
          </span>
          <span>{TRIAL ? 'Hospital feed, replayed' : 'Live demo hospital'}</span>
        </div>
        {/* No box of its own: its parts sit in the bar's grid, and its text is still the one sentence */}
        <div className="live-line" data-testid="live-line">
          <span className="live-ident">
            <span className="live-name">{HOSPITAL_NAME}</span>
            {said(`, ${feed}: `)}
            <span className="live-cadence">{cadence(live.every_minutes)}</span>
            {said('.')}
          </span>
          {last || next ? (
            <span className="live-timeline" data-ends={last && next ? 'both' : last ? 'last' : 'next'}>
              <span className="live-track" aria-hidden>
                {done !== null ? (
                  <span className="live-track-done" style={{ inlineSize: `${Math.round(done * 100)}%` }} />
                ) : null}
              </span>
              {last ? (
                <span className="live-point" data-point="last">
                  <span className="live-dot" aria-hidden key={pulse} data-pulse={pulse > 0 || undefined} />{' '}
                  <span className="live-point-label">Last</span>
                  {said(': ')}
                  <span className="live-point-line">
                    <span className="live-point-value">
                      {last.title ? (
                        <Tooltip label={last.title} withArrow events={HINT_EVENTS}>
                          <span className="live-story" tabIndex={0}>
                            {last.scenario}
                          </span>
                        </Tooltip>
                      ) : (
                        last.scenario
                      )}
                    </span>
                    {last.at ? (
                      <>
                        {said(', ')}
                        <span className="live-point-meta">{formatAge(last.at, now)}</span>
                      </>
                    ) : null}
                    {said('.')}
                  </span>
                </span>
              ) : null}
              {next ? (
                <span className="live-point" data-point="next">
                  <span className="live-node" aria-hidden /> <span className="live-point-label">Next</span>
                  {said(': ')}
                  <span className="live-point-line">
                    <span className="live-point-value">{next.scenario}</span>
                    {said(' ')}
                    <span className="live-point-meta">at {next.clock}</span>
                    {said('.')}
                  </span>
                </span>
              ) : null}
            </span>
          ) : null}
        </div>
        {action ? <div className="live-action">{action}</div> : null}
      </div>
      {note || resets || boardNote ? (
        <div className="live-notes">
          <div className="live-notes-row">
            {note ? (
              <Text size="xs" className="live-budget-line" data-testid="live-budget-line">
                {note}
              </Text>
            ) : null}
            {resets ? (
              // The instance goes back to its frozen image on the hour; no figure, since the first live reset sets it
              <Text size="xs" data-testid="live-reset-line">
                The demo resets on the hour: it is down for a few minutes, and anything you did is gone.
              </Text>
            ) : null}
            {boardNote}
          </div>
        </div>
      ) : null}
      <Suspense fallback={null}>
        {unavailable ? <LiveUnavailableNotice state={unavailable} className="live-unavailable" /> : null}
        {refusal && !TRIAL ? <StormNotice refusal={refusal} onClose={() => setRefusal(null)} /> : null}
        {storm && pathname !== '/incidents' ? <StormStrip storm={storm} /> : null}
      </Suspense>
    </div>
  );
}
