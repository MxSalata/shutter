import { Badge, Card, SimpleGrid, Stack, Text, Title } from '@mantine/core';
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

const COLOURS: Record<string, string> = {
  automatic: 'teal',
  approval: 'blue',
  per_chain: 'orange',
  board: 'grape',
};

/**
 * Who approves what, at a glance: one card per tier, each chain kind with how it is released. The value is always
 * written out, so the colour is never the only signal.
 */
export function PolicySummary({ profile }: { profile: SiteProfile }) {
  return (
    <Stack gap="xs">
      <Title order={2} fz="lg" id="site-summary-title">
        Who approves what
      </Title>
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
                      <Badge
                        color={COLOURS[value] ?? 'gray'}
                        variant="light"
                        style={{ textTransform: 'none', alignSelf: 'flex-start' }}
                      >
                        {POLICY_SHORT[value] ?? value}
                      </Badge>
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
        Automatic still means gated, rehearsed and verified: only the person's approval is left out. A tier
        not set for a kind needs one approval.
      </Text>
    </Stack>
  );
}
