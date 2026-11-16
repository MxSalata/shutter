import { Button, Group, List, Stack, Text } from '@mantine/core';
import { lazy, Suspense, useState } from 'react';
import { useSearchParams } from 'react-router';
import { readOnlyDemo } from '@/api/can';
import { useCan, useCasesOnce, useSiteEntries } from '@/api/hooks';
import { CLOSED_STATES, type SiteEntryItem, type SiteEntryState } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { NotYet, Section } from '@/components/Section';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { TRIAL } from '@/env/mode';
import { useDetail } from '@/stores/appearance';
import { formatZoned } from '@/lib/format';
import type { Tone } from '@/lib/tone';
import type { EntryBody } from './own/api';

/** The workbench (the editor, the proof, the dialogs) is its own chunk: only a reader who opens one loads it. */
const Workbench = lazy(() => import('./own/Workbench'));

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

/** The list's groups, in the order a person reads them: what applies, what waits, what is being written, what is gone. */
const GROUPS: { key: string; title: string; holds: (e: SiteEntryItem) => boolean }[] = [
  { key: 'waiting', title: 'Waiting for approval', holds: (e) => !!e.proposal },
  { key: 'active', title: 'Active', holds: (e) => e.state === 'active' || e.state === 'suspended' },
  { key: 'draft', title: 'Drafts', holds: (e) => e.state === 'draft' || e.state === 'proposed' },
  { key: 'retired', title: 'Retired', holds: (e) => e.state === 'retired' },
];

/** What an open proposal asks for, beside the entry's state. */
function proposalWords(e: SiteEntryItem): string | undefined {
  if (!e.proposal || e.state === 'proposed') return undefined;
  const what = { activate: `version ${e.proposal.version}`, retire: 'its retirement', resume: 'resuming it' }[
    e.proposal.action
  ];
  return `${what} waits for a second person's approval (proposed by ${e.proposal.by})`;
}

/**
 * The demo's example, shown where the online demo has no entry of its own: a failed transfer into Ward B with nothing
 * applied since, which S2's case shows and S1's does not. It is not stored; Try it previews it on those cases.
 */
const EXAMPLE: EntryBody = {
  title: 'A failed transfer into Ward B',
  priority: 10,
  scope: { ward: ['WARD-B'] },
  pattern: { event: ['transfer'], delivery: ['failed'], later_applied: ['none'] },
  why: 'The ward places its patients by hand this month, so a resend cannot know the bed is right.',
  team: '',
  instructions: "Ring the ward's nurse in charge before anything is entered. Do not resend.",
  prose: '',
  fixtures: [],
};

/** One entry of the list: its id and title, the sentence it comes to, who approved it and what it has stopped. */
function Entry({
  e,
  technical,
  onOpen,
}: {
  e: SiteEntryItem;
  technical: boolean;
  onOpen: (review: boolean) => void;
}) {
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
        <Text size="sm">
          {e.sentence ? `${e.sentence}.` : `${e.unreadable ?? "This entry's content cannot be read"}.`}
        </Text>
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
        <Group gap="xs" mt={2}>
          <Button
            size="compact-sm"
            variant="default"
            onClick={() => onOpen(false)}
            aria-label={`Open ${e.id}`}
          >
            Open
          </Button>
          {e.proposal ? (
            <Button
              size="compact-sm"
              variant="light"
              onClick={() => onOpen(true)}
              aria-label={`Review ${e.id}`}
            >
              Review
            </Button>
          ) : null}
        </Group>
      </Stack>
    </List.Item>
  );
}

/** The newest closed case of a scenario, for the demo's Try it. */
function useLatestClosed(scenario: string, enabled: boolean): string | undefined {
  const items = useCasesOnce({ scenario, limit: 10 }, enabled).data?.items ?? [];
  return items.find((c) => CLOSED_STATES.includes(c.state))?.caseId;
}

type Opened = { entryId?: string; fromCase?: string; example?: boolean; review?: boolean } | null;

/**
 * The site's own scenarios (CONTRACTS 6.8): each is a stop, which can only send a case to a person. The list says what
 * applies now, what waits for a second person, what is being written and what was retired, with a banner while one is
 * suspended or one person may approve their own. A person with the configure right writes one here or from a closed
 * case ("Make this one of our scenarios", `?own=new&case=`), proves it and sends it for approval; an approver reviews
 * it. On the demo the list and an example are read and tried, and saving is locked as the site profile's Save is.
 */
export function OwnScenarios() {
  const entries = useSiteEntries();
  const can = useCan();
  const technical = useDetail() === 'technical';
  const [search, setSearch] = useSearchParams();
  const [opened, setOpened] = useState<Opened>(() => {
    const own = search.get('own');
    if (own === 'new') return { fromCase: search.get('case') ?? undefined };
    if (own && /^L[1-9]\d*$/.test(own)) return { entryId: own };
    return null;
  });
  const items = entries.data?.items ?? [];
  const warnings = entries.data?.status.warnings ?? [];
  const demo = readOnlyDemo(can);
  const example = entries.isSuccess && !items.length && demo;
  const s2 = useLatestClosed('S2', example);
  const s1 = useLatestClosed('S1', example);
  const open = (o: Opened) => {
    setOpened(o);
    // The address keeps what is open, so a reload or a shared link opens it again; closing takes it off
    const next = new URLSearchParams(search);
    next.delete('own');
    next.delete('case');
    if (o?.entryId) next.set('own', o.entryId);
    else if (o && !o.example) {
      next.set('own', 'new');
      if (o.fromCase) next.set('case', o.fromCase);
    }
    setSearch(next, { replace: true });
  };
  const exampleBody: EntryBody = {
    ...EXAMPLE,
    fixtures: [
      ...(s2 ? [{ case: s2, expect: 'match' as const }] : []),
      ...(s1 ? [{ case: s1, expect: 'no_match' as const }] : []),
    ],
  };
  // The banner is the blocking kind while any protection is off or the matching of every case is held: a suspension (a
  // set-aside one included), the two-person rule lifted, or an entry the core could not read or recheck
  const suspended =
    (entries.data?.status.suspended.length ?? 0) > 0 ||
    !!entries.data?.status.onePerson ||
    warnings.some((w) => /could not be rechecked|cannot all be read/.test(w));
  return (
    <Section
      id="site-own-scenarios"
      title="Our own scenarios"
      wideNote
      note="A brake of this site's own: a case one matches goes to a person, with this site's instructions. It can never allow a resend."
    >
      <Stack gap="sm">
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
            <StatusNotice tone={suspended ? 'blocking' : 'attention'} title="For as long as this lasts">
              <List size="sm" spacing={2}>
                {warnings.map((w) => (
                  <List.Item key={w}>{w}</List.Item>
                ))}
              </List>
            </StatusNotice>
          </div>
        ) : null}
        {TRIAL && items.length ? (
          <Text size="sm" c="dimmed" data-testid="own-sample-note">
            Sample entries: a change lasts until you reload or leave.
          </Text>
        ) : null}
        {entries.isSuccess && !items.length ? (
          <NotYet>
            None yet: the shipped catalogue alone decides.
            {demo ? ' Try the example below on a scenario’s case.' : ' Start one from a closed case.'}
          </NotYet>
        ) : null}
        {GROUPS.map((g) => {
          const mine = items.filter(
            (e) => g.holds(e) && !GROUPS.slice(0, GROUPS.indexOf(g)).some((x) => x.holds(e)),
          );
          if (!mine.length) return null;
          return (
            <Stack gap={4} key={g.key} data-testid={`own-group-${g.key}`}>
              <Text component="h3" size="sm" fw={700} m={0}>
                {g.title}
              </Text>
              <List
                spacing="sm"
                listStyleType="none"
                data-testid={g.key === 'active' ? 'own-scenarios-list' : undefined}
              >
                {mine.map((e) => (
                  <Entry
                    key={e.id}
                    e={e}
                    technical={technical}
                    onOpen={(review) => open({ entryId: e.id, review })}
                  />
                ))}
              </List>
            </Stack>
          );
        })}
        {example ? (
          <Group gap="xs">
            <Button variant="default" onClick={() => open({ example: true })} data-testid="own-open-example">
              Read and try the example
            </Button>
          </Group>
        ) : null}
        {can.configure && !opened ? (
          <Group gap="xs">
            <Button variant="default" onClick={() => open({})} data-testid="own-new">
              Write one…
            </Button>
          </Group>
        ) : null}
        {opened ? (
          <Suspense fallback={<PageSkeleton label="Opening…" />}>
            <Workbench
              key={`${JSON.stringify(opened)}${opened.example ? `${s2 ?? ''}${s1 ?? ''}` : ''}`}
              entryId={opened.entryId}
              fromCase={opened.fromCase}
              review={opened.review}
              example={opened.example ? { title: `Example: ${EXAMPLE.title}`, body: exampleBody } : undefined}
              onClose={() => open(null)}
              onSaved={(id) => open({ entryId: id })}
            />
          </Suspense>
        ) : null}
      </Stack>
    </Section>
  );
}
