import { Anchor } from '@mantine/core';
import { IconArrowRight } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { Costs, Settings } from '@/api/types';
import { StatTile } from '@/components/StatTile';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { StatusBadge } from '@/components/StatusBadge';
import { SummaryBand } from '@/components/SummaryBand';
import { budgetSpent, budgetText, resetsHourly } from '@/lib/budget';
import { formatInt, formatUsd, plural } from '@/lib/format';
import { liveUnavailable } from '@/lib/liveAgents';
import { PROOF } from '@/lib/proof';
import { costRange, replayTile } from './settingsText';

/** The spent tile's caption on an instance that spends: against the cap, or what the figure counts. */
function spentCaption(s: Settings | undefined, words: ReturnType<typeof budgetText>, used: boolean): string {
  const b = s?.budget;
  if (!b || !words) return 'in all';
  const hourly = resetsHourly(s);
  if (used) return b.exhausted ? words.today : (words.share ?? words.today);
  if (b.dailyUsd > 0)
    return hourly ? `of the ${formatUsd(b.dailyUsd)} per reset` : `of today's ${formatUsd(b.dailyUsd)}`;
  return hourly ? 'since the demo last reset (every hour)' : 'today, no daily cap';
}

/**
 * The four figures a newcomer asks first, the real cost before the zeros (N22): what a board pass costs with the real
 * agents, what the recorded runs cost in all (both from the evaluation, through `lib/proof.ts`), what was spent here
 * and how many replayed runs cost nothing. A tile whose figure is missing is left out. Where money can be spent, the
 * spent tile takes the attention tone once the day's cap, or the user's share of it, is used up, or while the model
 * provider refuses the key; then the notice's words (until when, and on a demo how to install Shutter with one's own
 * key) stand in for its caption.
 */
export function SettingsTiles({ s, costs }: { s: Settings | undefined; costs: Costs | undefined }) {
  const totals = costs?.totals;
  const spent = totals?.spentUsd;
  const replay = replayTile(s, spent);
  const words = budgetText(s?.budget, { resetsHourly: resetsHourly(s) });
  const unavailable = replay ? null : liveUnavailable(s);
  const used = !replay && (budgetSpent(s?.budget) || !!unavailable);
  const realFigure = s?.budget ? s.budget.spentTodayUsd : spent;
  return (
    <SummaryBand title="Summary" cols={{ base: 2, md: 4 }}>
      {PROOF.costPerPass ? (
        <StatTile
          label="A board pass with real agents"
          figure={costRange(PROOF.costPerPass.min, PROOF.costPerPass.max)}
          caption="at list prices"
        >
          <Anchor component={Link} to="/evaluation" size="sm" underline="always">
            Evaluation <IconArrowRight size={14} aria-hidden style={{ verticalAlign: 'middle' }} />
          </Anchor>
        </StatTile>
      ) : null}
      {PROOF.runs !== null && PROOF.totalUsd !== null ? (
        <StatTile
          label="Recorded with the real agents"
          figure={plural(PROOF.runs, 'run')}
          caption={`${formatUsd(PROOF.totalUsd)} at list prices`}
        />
      ) : null}
      {replay && spent !== undefined ? (
        <StatTile label="Spent here" figure={formatUsd(spent)} caption="every answer here is a replay" />
      ) : null}
      {!replay && realFigure !== undefined ? (
        <StatTile
          label="Spent on real model runs"
          figure={formatUsd(realFigure)}
          caption={unavailable ? undefined : spentCaption(s, words, used)}
          tone={used ? 'attention' : undefined}
          status={
            used ? (
              <StatusBadge
                tone="attention"
                label={unavailable?.reason === 'service' ? 'Live agents unavailable' : 'Budget used up'}
              />
            ) : undefined
          }
        >
          {unavailable ? <LiveUnavailableNotice state={unavailable} variant="inline" compact /> : null}
        </StatTile>
      ) : null}
      {totals?.replayedRuns !== undefined ? (
        <StatTile label="Replayed runs" figure={formatInt(totals.replayedRuns)} caption="cost nothing" />
      ) : null}
    </SummaryBand>
  );
}
