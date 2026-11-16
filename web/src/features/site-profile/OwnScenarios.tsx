import { Group, List, Stack, Text } from '@mantine/core';
import { useSiteEntries } from '@/api/hooks';
import type { SiteEntryItem, SiteEntryState } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { NotYet, Section } from '@/components/Section';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { useDetail } from '@/stores/appearance';
import { formatZoned } from '@/lib/format';
import type { Tone } from '@/lib/tone';

const STATES: Record<SiteEntryState, { tone: Tone; label: string; hint: string }> = {
  active: { tone: 'positive', label: 'Active', hint: 'It applies: a case it matches goes to a person' },
  proposed: {
    tone: 'attention',
    label: 'Waiting for approval',
    hint: 'A second person has yet to approve it; it changes nothing until then',
  },
  draft: { tone: 'neutral', label: 'Draft', hint: 'A draft changes nothing' },
  suspended: {
    tone: 'blocking',
    label: 'Suspended',
    hint: 'One approver switched it off: its protection is off until a second person approves resuming it',
  },
  retired: {
    tone: 'neutral',
    label: 'Retired',
    hint: 'It no longer applies; its history is kept and its id is never used again',
  },
};

/** What an open proposal asks for, beside the entry's state. */
function proposalWords(e: SiteEntryItem): string | undefined {
  if (!e.proposal || e.state === 'proposed') return undefined;
  const what = { activate: `version ${e.proposal.version}`, retire: 'its retirement', resume: 'resuming it' }[
    e.proposal.action
  ];
  return `${what} waits for a second person's approval (proposed by ${e.proposal.by})`;
}

/** One entry of the list: its id and title, the sentence it comes to, who approved it and what it has stopped. */
function Entry({ e, technical }: { e: SiteEntryItem; technical: boolean }) {
  const state = STATES[e.state] ?? STATES.draft;
  const proposal = proposalWords(e);
  return (
    <List.Item data-testid={`own-scenario-${e.id}`}>
      <Stack gap={2}>
        <Group gap={6} wrap="wrap">
          <Text size="sm" fw={600}>
            {`${e.id}: ${e.title || 'untitled'}`}
          </Text>
          <StatusBadge tone={state.tone} label={state.label} hint={state.hint} />
          {e.needsReview ? (
            <StatusBadge
              tone="attention"
              label="Needs review"
              hint="An upgrade or a change of the site profile touched this entry. It still applies, and may match more cases than it was written for"
            />
          ) : null}
        </Group>
        <Text size="sm">{e.sentence ? `${e.sentence}.` : 'Its content could not be read.'}</Text>
        <Text size="sm" c="dimmed">
          {e.approvedBy
            ? `Version ${e.activeVersion} approved by ${e.approvedBy}${e.approvedAt ? `, ${formatZoned(e.approvedAt)}` : ''}. `
            : 'Not approved yet. '}
          {e.activeVersion > 0
            ? `${e.casesSent30} ${e.casesSent30 === 1 ? 'case' : 'cases'} sent to a person in the last 30 days.`
            : ''}
        </Text>
        {e.suspended ? (
          <Text size="sm">{`Suspended by ${e.suspended.by}, ${formatZoned(e.suspended.at)}: ${e.suspended.reason}`}</Text>
        ) : null}
        {proposal ? (
          <Text size="sm">{`${proposal.charAt(0).toUpperCase()}${proposal.slice(1)}.`}</Text>
        ) : null}
        {e.needsReview && e.review?.dropped?.length ? (
          <Text size="sm">
            {`No longer checked: ${e.review.dropped.map((d) => `${d.condition.replace(/_/g, ' ')} (${d.why})`).join('; ')}.`}
          </Text>
        ) : null}
        {/* Every note the recheck left, flagged or not: a fixture whose case is gone is said here too (design 7). */}
        {e.review?.notes?.length ? (
          <Text size="sm" data-testid={`own-scenario-${e.id}-notes`}>
            {e.review.notes.join(' ')}
          </Text>
        ) : null}
        {technical && e.content ? (
          <Text
            size="xs"
            c="dimmed"
            ff="monospace"
            style={{ overflowWrap: 'anywhere' }}
            data-testid={`own-scenario-${e.id}-pattern`}
          >
            {`pattern ${JSON.stringify(e.content.pattern)}${Object.keys(e.content.scope ?? {}).length ? ` scope ${JSON.stringify(e.content.scope)}` : ''} digest ${e.digest ?? ''}`}
          </Text>
        ) : null}
      </Stack>
    </List.Item>
  );
}

/**
 * The site's own scenarios (CONTRACTS 6.8), read only: each is a stop, which can only send a case to a person. The
 * list says what applies now, what waits for a second person, and what was suspended or flagged; the warnings stay for
 * as long as what they warn of lasts. Entries are written, proved, proposed and approved through the API in this release.
 */
export function OwnScenarios() {
  const entries = useSiteEntries();
  const technical = useDetail() === 'technical';
  const items = entries.data?.items ?? [];
  const warnings = entries.data?.status.warnings ?? [];
  return (
    <Section
      id="site-own-scenarios"
      title="Our own scenarios"
      wideNote
      note="A brake of this site's own: a case one matches goes to a person, with this site's instructions. It can never allow a resend."
    >
      {entries.isPending ? <PageSkeleton label="Loading our own scenarios…" /> : null}
      {entries.isError ? (
        <ErrorAlert
          error={entries.error}
          title="Our own scenarios could not be read"
          onRetry={() => void entries.refetch()}
        />
      ) : null}
      {warnings.length ? (
        <div data-testid="own-scenarios-warnings">
          <StatusNotice tone="attention" title="Check these">
            <List size="sm" spacing={2}>
              {warnings.map((w) => (
                <List.Item key={w}>{w}</List.Item>
              ))}
            </List>
          </StatusNotice>
        </div>
      ) : null}
      {entries.isSuccess && !items.length ? (
        <NotYet>
          None yet: the shipped catalogue alone decides. One is written, proved on stored cases and approved
          by a second person through the API (docs/CONTRACTS.md, section 6.8).
        </NotYet>
      ) : null}
      {items.length ? (
        <List spacing="sm" listStyleType="none" data-testid="own-scenarios-list">
          {items.map((e) => (
            <Entry key={e.id} e={e} technical={technical} />
          ))}
        </List>
      ) : null}
    </Section>
  );
}
