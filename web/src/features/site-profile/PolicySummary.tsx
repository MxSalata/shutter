import { Card, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconFileDescription, IconUserCheck, IconUsers, type Icon } from '@tabler/icons-react';
import { StatusBadge } from '@/components/StatusBadge';
import type { Tone } from '@/lib/tone';
import type { SiteProfile } from '@/api/types';
import {
  KINDS,
  KIND_LABELS,
  POLICY_SHORT,
  TIERS,
  TIER_LABELS,
  closeNeedsApprover,
  receiversAt,
} from './profile';

/** How a kind is released: by the site's written policy (information, so it stands out), else by people. */
const RELEASES: Record<string, { tone: Tone; icon: Icon }> = {
  automatic: { tone: 'info', icon: IconFileDescription },
  approval: { tone: 'neutral', icon: IconUserCheck },
  per_chain: { tone: 'neutral', icon: IconUserCheck },
  board: { tone: 'neutral', icon: IconUsers },
};

/**
 * Who releases what, at a glance: one card per tier, each chain kind with how it is released. The value is always
 * written out, so the colour is never the only signal.
 */
export function PolicySummary({ profile }: { profile: SiteProfile }) {
  return (
    <Stack gap="xs" data-tour="site-summary">
      <Title order={2} fz="lg" id="site-summary-title">
        Who releases each write
      </Title>
      <Text size="sm" c="dimmed">
        Every write passes the gate first; then a person, or the site's written policy, releases it.
      </Text>
      {/* What a chain is, before the cards use the word */}
      <Text size="xs" c="dimmed">
        When many deliveries fail together, an incident groups them, and each encounter&apos;s failures form a
        chain, sent in event order. A single failure is one failure with nothing applied after it; an ordered
        chain is several failures with no successful delivery between them; an interleaved chain has
        successful deliveries between its failures, or a later event already applied.
      </Text>
      <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm" role="list" aria-labelledby="site-summary-title">
        {TIERS.map((tier) => {
          const receivers = receiversAt(profile, tier);
          return (
            <Card key={tier} padding="sm" withBorder role="listitem">
              <Stack gap={6}>
                <Text fw={600}>Tier {TIER_LABELS[tier]}</Text>
                <Text size="xs" c="dimmed">
                  {receivers.length ? `Receivers: ${receivers.join(', ')}` : 'No receiver at this tier'}
                </Text>
                {KINDS.map((kind) => {
                  const value = profile.policy?.[tier]?.[kind] ?? 'approval';
                  return (
                    <Stack key={kind} gap={2}>
                      <Text size="sm">{KIND_LABELS[kind][0].toUpperCase() + KIND_LABELS[kind].slice(1)}</Text>
                      <span style={{ alignSelf: 'flex-start' }}>
                        <StatusBadge
                          {...(RELEASES[value] ?? { tone: 'neutral' })}
                          label={
                            value === 'automatic'
                              ? "automatic: the site's written policy"
                              : (POLICY_SHORT[value] ?? value)
                          }
                        />
                      </span>
                    </Stack>
                  );
                })}
              </Stack>
            </Card>
          );
        })}
      </SimpleGrid>
      <Text size="sm">
        A case the team corrected by hand is marked handled by{' '}
        {closeNeedsApprover(profile)
          ? 'an approver only (the two-person rule)'
          : 'an operator or an approver'}
        .
      </Text>
      <Text size="xs" c="dimmed">
        Automatic means the site's written policy releases the write: it is still gated, rehearsed and
        verified, only the person's approval is left out. A tier not set for a kind needs one approval.
      </Text>
    </Stack>
  );
}
