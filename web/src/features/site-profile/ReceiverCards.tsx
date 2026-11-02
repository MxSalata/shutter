import { Badge, Card, Group, List, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconCircleDashed, IconX } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import type { ReceiverCategory, SiteProfile, SiteReceiver } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import {
  CATEGORIES,
  CATEGORY_TEXT,
  HISTORY_POLICY_TEXT,
  categoryOf,
  derivedPolicy,
  historyPolicyOf,
} from '@/lib/categories';
import { categoryMark, hueVar } from '@/lib/hues';
import { TIER_LABELS, overtakenLine } from './profile';

/** The category's mark: its icon in its identity hue on a round surface, dashed for a kind not modelled yet. */
export function CategoryAvatar({ category }: { category: ReceiverCategory }) {
  const { hue, icon: I, dashed } = categoryMark(category);
  return (
    <span
      className="identity-mark"
      aria-hidden
      data-category={category}
      style={{
        width: 32,
        height: 32,
        borderRadius: '50%',
        ['--mark-hue' as string]: hueVar(hue),
        outline: dashed ? '1.5px dashed var(--mantine-color-dimmed)' : undefined,
        outlineOffset: -1,
      }}
    >
      <I size={18} stroke={1.8} />
    </span>
  );
}

/** Three 6 px segments, filled in teal up to the tier: a picture of "how sensitive", always beside the tier's words. */
export function TierMeter({ tier }: { tier: number }) {
  return (
    <span aria-hidden data-tier={tier} style={{ display: 'inline-flex', gap: 3, alignItems: 'center' }}>
      {[1, 2, 3].map((n) => (
        <span
          key={n}
          data-filled={n <= tier || undefined}
          style={{
            width: 14,
            height: 6,
            borderRadius: 3,
            background: n <= tier ? 'var(--shutter-hue-teal)' : 'var(--mantine-color-default-border)',
          }}
        />
      ))}
    </span>
  );
}

/** The tier as a neutral outline badge with its meter. */
export function TierMark({ tier }: { tier: string | number }) {
  const t = String(tier);
  return (
    <Group gap={6} wrap="nowrap">
      <Badge
        variant="outline"
        color="gray"
        size="sm"
        style={{ textTransform: 'none', color: 'var(--mantine-color-text)' }}
      >
        Tier {TIER_LABELS[t] ?? t}
      </Badge>
      <TierMeter tier={Number(t)} />
    </Group>
  );
}

interface Capability {
  yes: boolean;
  /** For the "Takes:" line. */
  short: string;
  /** For "What it cannot take": the whole meaning. */
  long: ReactNode;
}

/** What the receiver can take, as the site declared it. */
function capabilities(r: SiteReceiver, withTerms: boolean): Capability[] {
  const f = r.features;
  // No features declared: the core assumes every one, as the downstream system's defaults
  const has = (k: string) => (f ? f[k] === true : true);
  const a = (code: string) => (withTerms ? <Term term="adt">{code}</Term> : code);
  return [
    {
      yes: has('conditional_writes'),
      short: 'conditional writes',
      long: 'Conditional writes: a write names the version it expects',
    },
    { yes: has('receipts'), short: 'receipts', long: 'Receipts: it says whether an operation was committed' },
    { yes: has('history'), short: 'history', long: 'A readable history of each encounter' },
    { yes: has('dry_run'), short: 'dry runs', long: 'Dry runs: a write rehearsed and rolled back' },
    {
      yes: r.cancels === true,
      short: 'cancels',
      long: <>Cancels ({a('A11')}, A12, A13)</>,
    },
    {
      yes: r.merges === true,
      short: 'merges',
      long: <>Merges ({a('A40')}), when the site allows them</>,
    },
  ];
}

function ReceiverCard({
  r,
  profile,
  i,
  withTerms,
}: {
  r: SiteReceiver;
  profile: SiteProfile;
  i: number;
  withTerms: boolean;
}) {
  const category = categoryOf(r);
  const text = CATEGORY_TEXT[category];
  const policy = historyPolicyOf(r, profile);
  const overridden = !!r.history_policy && policy !== derivedPolicy(category);
  // An entry with neither a category nor its own policy is read as current state, with the deprecated site-wide policy
  const unanswered = !r.history_policy && (r.category === undefined || r.category === '');
  const titleId = `site-receiver-card-${i}`;
  const caps = capabilities(r, withTerms);
  const takes = caps.filter((c) => c.yes);
  const cannot = caps.filter((c) => !c.yes);
  // The long sentence is what the case page and the tests have always read; the line above it is the plain form
  const longWords =
    category === 'orders_results'
      ? text.overtaken
      : policy === 'correct'
        ? CATEGORY_TEXT.history_of_record.overtaken
        : CATEGORY_TEXT.current_state.overtaken;
  const endpoints = r.api
    ? Object.entries(r.api)
        .map(([k, v]) => `${k} ${v}`)
        .join(' · ')
    : 'the downstream system’s defaults';
  return (
    <Card
      withBorder
      padding="md"
      role="listitem"
      aria-labelledby={titleId}
      data-category={category}
      style={text.modelled ? undefined : { borderStyle: 'dashed' }}
    >
      <Stack gap="xs">
        <Group gap="sm" wrap="nowrap" align="center">
          <CategoryAvatar category={category} />
          <Stack gap={0} style={{ minWidth: 0 }}>
            <Title order={4} id={titleId}>
              {r.name || 'A new receiver'}
            </Title>
            <Text size="sm" c="dimmed">
              {r.system || 'What it does is not answered yet'}
            </Text>
          </Stack>
        </Group>
        <Group gap="xs" align="center">
          <Text size="sm" fw={600}>
            {text.label}
          </Text>
          <Text size="sm" c="dimmed" aria-hidden>
            ·
          </Text>
          <TierMark tier={r.tier} />
        </Group>
        {unanswered || !text.modelled ? (
          <Group gap={6}>
            {unanswered ? (
              <StatusBadge tone="neutral" label={`Not answered: read as ${text.label.toLowerCase()}`} />
            ) : null}
            {!text.modelled ? (
              <StatusBadge tone="neutral" icon={IconCircleDashed} label="Not modelled yet" />
            ) : null}
          </Group>
        ) : null}
        <Text size="md">{text.gist}.</Text>
        <Text size="md">{overtakenLine(category, policy)}</Text>
        {overridden ? (
          <Text size="sm" c="dimmed">
            {`Set on this receiver: ${policy === 'correct' ? 'correct the history' : 'keep what is current'}, not what its category gives.`}
          </Text>
        ) : null}
        {unanswered ? (
          <Text size="sm" c="dimmed">
            {`Read from the site-wide history policy (${HISTORY_POLICY_TEXT[policy]}), since no category is answered for this receiver.`}
          </Text>
        ) : null}
        {category === 'orders_results' ? null : (
          <Text size="sm">
            Takes: {takes.length ? takes.map((c) => c.short).join(', ') : 'nothing declared'}.
          </Text>
        )}
        {category !== 'orders_results' && cannot.length ? (
          <TechDetail label="What it cannot take" kind="explain">
            <List size="sm" spacing={2} listStyleType="none" ml={0} pl={0}>
              {cannot.map((c) => (
                <List.Item
                  key={c.short}
                  icon={<IconX size={14} aria-hidden style={{ color: 'var(--mantine-color-dimmed)' }} />}
                >
                  <Text span size="sm" c="dimmed">
                    {c.long}
                  </Text>
                </List.Item>
              ))}
            </List>
          </TechDetail>
        ) : null}
        <TechDetail label="History policy and endpoints" kind="data">
          <Stack gap={4}>
            <Text size="sm">
              History policy: {HISTORY_POLICY_TEXT[policy]}
              {r.history_policy ? ' (set on this receiver)' : ' (from its category)'}. {longWords}
            </Text>
            <Text size="sm">
              Endpoints: <CodeChip>{endpoints}</CodeChip>
            </Text>
          </Stack>
        </TechDetail>
      </Stack>
    </Card>
  );
}

/** A category no receiver has: listed so the profile reads as a whole. */
function AbsentCategory({ category }: { category: ReceiverCategory }) {
  const text = CATEGORY_TEXT[category];
  return (
    <Card
      withBorder
      padding="md"
      role="listitem"
      style={{ borderStyle: 'dashed' }}
      data-category={category}
      aria-label={text.label}
    >
      <Stack gap="xs">
        <Group gap="sm" wrap="nowrap" align="center">
          <CategoryAvatar category={category} />
          <Title order={4}>{text.label}</Title>
        </Group>
        <Group gap={6}>
          <StatusBadge
            tone="neutral"
            icon={IconCircleDashed}
            label={text.modelled ? 'No receiver of this kind' : 'Not modelled yet'}
          />
        </Group>
        <Text size="md">{text.gist}.</Text>
        <Text size="md">{overtakenLine(category, derivedPolicy(category))}</Text>
      </Stack>
    </Card>
  );
}

/**
 * Each receiver as a card: its category in plain words, its tier with a meter, what an overtaken failure does to it and
 * what it can take. A category no receiver has follows, dashed, so the three kinds read as a whole. Who releases a
 * write is the matrix's, below.
 */
export function ReceiverCards({ profile }: { profile: SiteProfile }) {
  const present = new Set(profile.receivers.map(categoryOf));
  const absent = CATEGORIES.filter((c) => !present.has(c));
  return (
    <Stack gap="sm" data-tour="site-receivers-cards">
      <Stack gap={2}>
        <Title order={3} id="site-receivers-title">
          The receivers and what each needs
        </Title>
        <Text size="md" c="dimmed" maw="68ch">
          The <Term term="receiver-kind">category</Term> sets what an overtaken failure does; the tier sets
          who releases a write.
        </Text>
      </Stack>
      <SimpleGrid
        cols={{ base: 1, sm: 2, lg: 3 }}
        spacing="sm"
        role="list"
        aria-labelledby="site-receivers-title"
        style={{ alignItems: 'start' }}
      >
        {profile.receivers.map((r, i) => (
          <ReceiverCard key={i} r={r} profile={profile} i={i} withTerms={i === 0} />
        ))}
        {absent.map((c) => (
          <AbsentCategory key={c} category={c} />
        ))}
      </SimpleGrid>
    </Stack>
  );
}
