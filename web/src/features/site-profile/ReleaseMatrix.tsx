import { Group, Stack, Table, Text, Title, VisuallyHidden } from '@mantine/core';
import type { SiteProfile } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { StackTable } from '@/components/StackTable';
import { StatusBadge } from '@/components/StatusBadge';
import { Term } from '@/components/Term';
import { categoryOf } from '@/lib/categories';
import { glossary } from '@/lib/glossary';
import { release } from '@/lib/status';
import { useTechnical } from '@/stores/appearance';
import { KINDS, KIND_TERMS, TIERS, TIER_NAMES } from './profile';

/** The receivers at a tier, by name; one whose cases go to a person says so, since no case writes to it. */
function receiversAtTier(profile: SiteProfile, tier: string): string[] {
  return profile.receivers
    .filter((r) => String(r.tier) === tier)
    .map((r) => {
      const name = r.name || 'unnamed';
      return categoryOf(r) === 'orders_results' ? `${name} (no resend from a case)` : name;
    });
}

/**
 * Who releases a write of each kind at each tier, as a table a person can read down: the tiers by name with their
 * receivers, the kinds of failure in plain words (with the code's own names beside them in Technical), and in every cell
 * a badge with its icon and words from the one shared map. On a phone each tier is a card.
 */
export function ReleaseMatrix({ profile }: { profile: SiteProfile }) {
  const technical = useTechnical();
  return (
    <Stack gap="sm" component="section" data-tour="site-summary" aria-labelledby="site-summary-title">
      <Stack gap={2}>
        <Title order={3} id="site-summary-title">
          Who releases each write
        </Title>
        <Text size="md" c="dimmed" maw="68ch">
          Every write passes the <Term term="gate">gate</Term> first. Then, for each{' '}
          <Term term="tier">tier</Term>:
        </Text>
      </Stack>
      <Table.ScrollContainer minWidth={520} className="stack-scroll">
        <StackTable className="stack-table" verticalSpacing="sm" aria-labelledby="site-summary-title">
          <Table.Caption>
            <VisuallyHidden>Who releases each write</VisuallyHidden>
          </Table.Caption>
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th scope="col">Tier</StackTable.Th>
              {KINDS.map((kind) => (
                <StackTable.Th key={kind} scope="col">
                  <Group gap={6} wrap="wrap">
                    <Term term={KIND_TERMS[kind]} />
                    {technical ? <CodeChip>{kind}</CodeChip> : null}
                  </Group>
                </StackTable.Th>
              ))}
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {TIERS.map((tier) => {
              const receivers = receiversAtTier(profile, tier);
              return (
                <StackTable.Tr key={tier}>
                  <StackTable.Th scope="row" display={{ base: 'block', xs: 'table-cell' }}>
                    <Text size="md" fw={600}>
                      Tier {tier}: {TIER_NAMES[tier]}
                    </Text>
                    <Text size="sm" c="dimmed" fw={400}>
                      {receivers.length ? receivers.join(', ') : 'No receivers'}
                    </Text>
                  </StackTable.Th>
                  {KINDS.map((kind) => (
                    <StackTable.Td key={kind} data-label={glossary(KIND_TERMS[kind]).term}>
                      <StatusBadge {...release(profile.policy?.[tier]?.[kind] ?? 'approval')} />
                    </StackTable.Td>
                  ))}
                </StackTable.Tr>
              );
            })}
          </StackTable.Tbody>
        </StackTable>
      </Table.ScrollContainer>
      <Text size="sm" c="dimmed" maw="68ch">
        When the board decides, a board of agents weighs the case and a person releases its plan.
      </Text>
    </Stack>
  );
}
