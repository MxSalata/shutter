import { Card, Group, List, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import {
  IconCheck,
  IconCircleDashed,
  IconFileDescription,
  IconUserCheck,
  IconUsers,
  IconX,
  type Icon,
} from '@tabler/icons-react';
import type { ChainKind, ReceiverCategory, SiteProfile, SiteReceiver } from '@/api/types';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import {
  CATEGORIES,
  CATEGORY_TEXT,
  HISTORY_POLICY_TEXT,
  categoryOf,
  derivedPolicy,
  historyPolicyOf,
} from '@/lib/categories';
import type { Tone } from '@/lib/tone';
import { KINDS, KIND_LABELS, TIER_LABELS } from './profile';

/** Who releases a write of a chain kind, in words: a person, the board, or the site's written policy. */
const RELEASE: Record<string, { tone: Tone; icon: Icon; label: string }> = {
  automatic: { tone: 'info', icon: IconFileDescription, label: "The site's written policy" },
  approval: { tone: 'attention', icon: IconUserCheck, label: 'A person, one approval' },
  per_chain: { tone: 'attention', icon: IconUserCheck, label: 'A person, one approval per chain' },
  board: { tone: 'neutral', icon: IconUsers, label: 'The board of specialists decides' },
};

const sentence = (kind: ChainKind) => KIND_LABELS[kind][0].toUpperCase() + KIND_LABELS[kind].slice(1);

/** What the receiver can take, as the site declared it: each line says yes or no in words. */
function capabilities(r: SiteReceiver): [boolean, string][] {
  const f = r.features;
  // No features declared: the core assumes every one, as the downstream system's defaults
  const has = (k: string) => (f ? f[k] === true : true);
  return [
    [has('conditional_writes'), 'Conditional writes: a write names the version it expects'],
    [has('receipts'), 'Receipts: it says whether an operation was committed'],
    [has('history'), 'A readable history of each encounter'],
    [has('dry_run'), 'Dry runs: a write rehearsed and rolled back'],
    [r.cancels === true, 'Cancels (A11, A12, A13)'],
    [r.merges === true, 'Merges (A40), when the site allows them'],
  ];
}

function ReceiverCard({ r, profile, i }: { r: SiteReceiver; profile: SiteProfile; i: number }) {
  const category = categoryOf(r);
  const text = CATEGORY_TEXT[category];
  const policy = historyPolicyOf(r, profile);
  const overridden = !!r.history_policy && policy !== derivedPolicy(category);
  // An entry with neither a category nor its own policy is read as current state, with the deprecated site-wide policy
  const unanswered = !r.history_policy && (r.category === undefined || r.category === '');
  const tier = String(r.tier);
  const titleId = `site-receiver-card-${i}`;
  return (
    <Card
      withBorder
      padding="md"
      role="listitem"
      aria-labelledby={titleId}
      data-category={category}
      style={text.modelled ? undefined : { borderStyle: 'dashed' }}
    >
      <Stack gap="sm">
        <Stack gap={4}>
          <Group gap={6}>
            <StatusBadge
              tone={text.modelled ? 'info' : 'neutral'}
              icon={text.modelled ? undefined : IconCircleDashed}
              label={
                unanswered
                  ? `Not answered: read as ${text.label.toLowerCase()}`
                  : text.modelled
                    ? text.label
                    : `${text.label}: not modelled yet`
              }
            />
          </Group>
          <Title order={3} fz="md" id={titleId}>
            {r.name || 'A new receiver'}
          </Title>
          <Text size="sm" c="dimmed">
            {r.system || 'What it does is not answered yet'}
          </Text>
          <Text size="sm">
            {text.gist}. {text.examples}.
          </Text>
        </Stack>
        <Stack gap={4}>
          <Text size="xs" fw={700} tt="uppercase" c="dimmed">
            When a failure is overtaken
          </Text>
          <Text size="sm">
            {category === 'orders_results'
              ? text.overtaken
              : policy === 'correct'
                ? CATEGORY_TEXT.history_of_record.overtaken
                : CATEGORY_TEXT.current_state.overtaken}
          </Text>
          {overridden ? (
            <Text size="xs" c="dimmed">
              {`Set on this receiver: ${policy === 'correct' ? 'correct the history' : 'keep what is current'}, not what its category gives.`}
            </Text>
          ) : null}
          {unanswered ? (
            <Text size="xs" c="dimmed">
              {`Read from the site-wide history policy (${HISTORY_POLICY_TEXT[policy]}), since no category is answered for this receiver.`}
            </Text>
          ) : null}
        </Stack>
        <Stack gap={4}>
          <Text size="xs" fw={700} tt="uppercase" c="dimmed">
            Who releases a write, at tier {TIER_LABELS[tier] ?? tier}
          </Text>
          {category === 'orders_results' ? (
            <Text size="sm">
              Nobody: Shutter writes nothing to it. Every failure goes to a person, and the gate blocks any
              write (RECEIVER_NOT_MODELLED).
            </Text>
          ) : (
            <Stack gap={6}>
              {KINDS.map((kind) => {
                const value = profile.policy?.[tier]?.[kind] ?? 'approval';
                const release = RELEASE[value] ?? { tone: 'neutral' as Tone, icon: IconUsers, label: value };
                return (
                  <Group key={kind} gap={6} justify="space-between" wrap="wrap">
                    <Text size="sm">{sentence(kind)}</Text>
                    <StatusBadge {...release} />
                  </Group>
                );
              })}
              <Text size="xs" c="dimmed">
                Every write passes the gate, a rehearsal and the verifier, whoever releases it.
              </Text>
            </Stack>
          )}
        </Stack>
        <Stack gap={4}>
          <Text size="xs" fw={700} tt="uppercase" c="dimmed">
            What it can take
          </Text>
          <List size="sm" spacing={2} listStyleType="none" ml={0} pl={0}>
            {capabilities(r).map(([yes, what]) => (
              <List.Item
                key={what}
                icon={
                  yes ? (
                    <IconCheck size={14} aria-hidden style={{ color: 'var(--mantine-color-green-text)' }} />
                  ) : (
                    <IconX size={14} aria-hidden style={{ color: 'var(--mantine-color-dimmed)' }} />
                  )
                }
              >
                <Text span size="sm" c={yes ? undefined : 'dimmed'}>
                  {`${yes ? 'Yes' : 'No'}: ${what}`}
                </Text>
              </List.Item>
            ))}
          </List>
        </Stack>
      </Stack>
    </Card>
  );
}

/** A category no receiver has: listed so the profile reads as a whole. */
function AbsentCategory({ category }: { category: ReceiverCategory }) {
  const text = CATEGORY_TEXT[category];
  return (
    <Card withBorder padding="md" role="listitem" style={{ borderStyle: 'dashed' }} data-category={category}>
      <Stack gap={4}>
        <Group gap={6}>
          <StatusBadge
            tone="neutral"
            icon={IconCircleDashed}
            label={text.modelled ? 'No receiver of this kind' : 'Not modelled yet'}
          />
        </Group>
        <Title order={3} fz="md">
          {text.label}
        </Title>
        <Text size="sm">
          {text.gist}. {text.examples}.
        </Text>
        <Text size="sm" c="dimmed">
          {text.overtaken}
        </Text>
      </Stack>
    </Card>
  );
}

/**
 * Each receiver as a card: its category in plain words, what an overtaken failure does to it, who releases a write at
 * its tier and what it can take. A category no receiver has follows, dashed, so the three kinds read as a whole.
 */
export function ReceiverCards({ profile }: { profile: SiteProfile }) {
  const present = new Set(profile.receivers.map(categoryOf));
  const absent = CATEGORIES.filter((c) => !present.has(c));
  return (
    <Stack gap="xs" data-tour="site-receivers-cards">
      <Title order={2} fz="lg" id="site-receivers-title">
        The receivers and what each needs
      </Title>
      <StatusNotice tone="info" title="Three kinds of receiver">
        Each receiver is one system with one category, asked below. The category sets what Shutter does with a
        failure a later event has overtaken; the receiver&apos;s tier sets who releases each write: a person,
        or the site&apos;s written policy.
      </StatusNotice>
      <SimpleGrid
        cols={{ base: 1, sm: 2, lg: 3 }}
        spacing="sm"
        role="list"
        aria-labelledby="site-receivers-title"
      >
        {profile.receivers.map((r, i) => (
          <ReceiverCard key={i} r={r} profile={profile} i={i} />
        ))}
        {absent.map((c) => (
          <AbsentCategory key={c} category={c} />
        ))}
      </SimpleGrid>
    </Stack>
  );
}
