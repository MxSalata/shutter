import { Stack, Text, Tooltip } from '@mantine/core';
import type { IncidentDetail } from '@/api/types';
import { HeroBand } from '@/components/HeroBand';
import { StatTile } from '@/components/StatTile';
import { SummaryBand } from '@/components/SummaryBand';
import { Term } from '@/components/Term';
import { formatDuration, formatTime, plural } from '@/lib/format';
import { incidentOutcome } from '@/lib/status';
import { HINT_EVENTS } from '@/theme';
import { decidedBy, describeKinds, heroSentence, openToClosed } from '../describe';

/** "Site policy: chains 1, 3, 4. The board: chain 2.": which chain each count is. */
const whichChains = (deciders: ReturnType<typeof decidedBy>['deciders']) =>
  deciders
    .map((d) => `${d.label}: ${d.seqs.length === 1 ? 'chain' : 'chains'} ${d.seqs.join(', ')}`)
    .join('. ') + '.';

/**
 * What a manager measures first (N21): the hero sentence in the incident outcome's tone, then four tiles, the time from
 * opening to closing leading: the failures, the chains, and who decided them.
 */
export function IncidentHero({ inc }: { inc: IncidentDetail }) {
  const outcome = incidentOutcome(inc);
  const p = inc.progress;
  const ms = openToClosed(inc);
  const { deciders, approvals } = decidedBy(inc.chains);
  const [top, ...rest] = deciders;
  return (
    <HeroBand tone={outcome.tone} statement={heroSentence(inc)} label="Outcome">
      <SummaryBand title="The incident in figures" cols={{ base: 2, md: 4 }}>
        <StatTile
          label="Open to closed"
          figure={ms === undefined ? 'Still open' : formatDuration(ms)}
          caption={
            inc.closedAt
              ? `${formatTime(inc.openedAt)} to ${formatTime(inc.closedAt)}`
              : `since ${formatTime(inc.openedAt)}`
          }
        />
        <StatTile label="Failures" figure={p?.cases ?? 0} caption={`to ${inc.receiver}`} />
        <StatTile
          label={<Term term="chain">Chains</Term>}
          figure={p?.chains ?? 0}
          caption={p?.chains ? describeKinds(inc) : 'they form when intake closes'}
        />
        {top ? (
          <StatTile
            label="Decided by"
            figure={`${top.seqs.length} of ${inc.chains.length}`}
            caption={`by ${top.label.toLowerCase()}`}
          >
            <Tooltip label={whichChains(deciders)} multiline maw={320} events={HINT_EVENTS}>
              <Stack gap={0} tabIndex={0}>
                {rest.map((d) => (
                  <Text size="sm" key={d.key}>
                    {d.label} {d.seqs.length}
                  </Text>
                ))}
                <Text size="sm">{approvals ? plural(approvals, 'approval') : 'No approval needed'}</Text>
              </Stack>
            </Tooltip>
          </StatTile>
        ) : null}
      </SummaryBand>
    </HeroBand>
  );
}
