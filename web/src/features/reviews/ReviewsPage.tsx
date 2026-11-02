import { Anchor, Badge, Group, Paper, SimpleGrid, Stack, Table, Text, Title } from '@mantine/core';
import { IconClipboardSearch } from '@tabler/icons-react';
import { useId } from 'react';
import { Link } from 'react-router';
import { useMe, useReviews } from '@/api/hooks';
import type { ReviewListItem } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { EmptyState } from '@/components/EmptyState';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Section } from '@/components/Section';
import { StackTable } from '@/components/StackTable';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import { TRIAL } from '@/env/mode';
import { AgentStateBadge, ReviewStateBadge, SeverityCounts } from './badges';
import { latestPerProduction, READ_ONLY } from './review';
import { StartReview } from './StartReview';
import './reviews.css';

/** What the long lead said before the page had a short one: what a review reads, and that it only reads. */
const WHAT_IS_READ = `One read-only pass over a production Shutter runs or watches: the effective value of the settings that decide whether a failure is retried, seen and kept in order, the message purge task, and the window's errors and failed messages, each tied to the cases Shutter opened. ${READ_ONLY}`;

/** The row's edge: a review that failed is blocking, one still running is information, a finished one is neutral. */
const rowTone = (r: ReviewListItem) =>
  r.state === 'failed' ? 'blocking' : r.state === 'done' ? undefined : 'info';

function ReviewRow({ r }: { r: ReviewListItem }) {
  return (
    <StackTable.Tr className="tone-row" data-tone={rowTone(r)}>
      <StackTable.Td>
        <Anchor component={Link} to={`/reviews/${encodeURIComponent(r.reviewId)}`} fw={600} size="sm">
          {r.reviewId}
        </Anchor>
      </StackTable.Td>
      <StackTable.Td data-label="Production">
        <Text size="sm">{r.production}</Text>
        <Text size="xs" c="dimmed">
          {r.namespace}
        </Text>
      </StackTable.Td>
      <StackTable.Td data-label="State" data-label-hidden>
        <Group gap={4} wrap="wrap">
          <ReviewStateBadge state={r.state} />
          <AgentStateBadge state={r.agentState} />
        </Group>
      </StackTable.Td>
      <StackTable.Td data-label="Findings" data-label-hidden className="stack-line">
        <SeverityCounts summary={r.summary} />
      </StackTable.Td>
      <StackTable.Td data-label="Started" className="stack-meta">
        <Timestamp iso={r.startedAt} age />
      </StackTable.Td>
      <StackTable.Td data-label="Requested by" className="stack-meta">
        <Text size="sm" span>
          {r.requestedBy}
        </Text>
      </StackTable.Td>
    </StackTable.Tr>
  );
}

/** The newest review of one production: its findings by severity, which review it is and when it started. */
function LatestReview({ r }: { r: ReviewListItem }) {
  return (
    <Paper p="md" className="latest-review">
      <Stack gap="xs">
        <Group gap="xs" wrap="wrap" align="center">
          <Text fw={600}>{r.production}</Text>
          <CodeChip>{r.namespace}</CodeChip>
        </Group>
        {r.state === 'done' ? <SeverityCounts summary={r.summary} /> : <ReviewStateBadge state={r.state} />}
        <Group gap="xs" wrap="wrap" align="center">
          <Anchor component={Link} to={`/reviews/${encodeURIComponent(r.reviewId)}`} size="sm">
            Open {r.reviewId}
          </Anchor>
          <Timestamp iso={r.startedAt} size="sm" c="dimmed" />
          <AgentStateBadge state={r.agentState} />
        </Group>
      </Stack>
    </Paper>
  );
}

function LatestPerProduction({ items }: { items: ReviewListItem[] }) {
  const id = useId();
  return (
    <section aria-labelledby={id} id="latest">
      <Title order={2} id={id} mb="xs">
        Latest per production
      </Title>
      <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm" style={{ alignItems: 'stretch' }}>
        {latestPerProduction(items).map((r) => (
          <LatestReview key={`${r.namespace}|${r.production}`} r={r} />
        ))}
      </SimpleGrid>
    </section>
  );
}

export default function ReviewsPage() {
  const me = useMe();
  const reviews = useReviews({ limit: 100 });
  const items = reviews.data?.items ?? [];
  const startNote = me.data?.operator
    ? TRIAL
      ? 'The trial replays a recorded review.'
      : null
    : 'An operator starts a review.';
  return (
    <>
      <PageHeader
        title="Production review"
        icon={IconClipboardSearch}
        hue="violet"
        lead={
          <>
            A read-only check of a <Term term="production">production</Term>&apos;s settings and recent
            errors, tied to the cases.
          </>
        }
        details={WHAT_IS_READ}
        actions={
          me.data ? (
            <Stack gap={4} align="flex-end" data-tour="reviews-start">
              {me.data.operator ? <StartReview /> : null}
              {startNote ? (
                <Text size="sm" c="dimmed">
                  {startNote}
                </Text>
              ) : null}
            </Stack>
          ) : null
        }
      />
      <Stack gap="md">
        {items.length > 0 ? <LatestPerProduction items={items} /> : null}
        <Section
          id="past"
          tour="reviews-past"
          title="Past reviews"
          note="Newest first; the last 50 of each production are kept."
          aside={
            reviews.data ? (
              <Badge variant="light" color="gray" style={{ textTransform: 'none' }}>
                {reviews.data.total}
              </Badge>
            ) : null
          }
        >
          {reviews.isPending ? <PageSkeleton label="Loading the reviews…" /> : null}
          {reviews.isError ? (
            <ErrorAlert
              error={reviews.error}
              title="The reviews could not be read"
              onRetry={() => void reviews.refetch()}
            />
          ) : null}
          {reviews.data && items.length === 0 ? (
            <EmptyState icon={IconClipboardSearch} hue="violet">
              No reviews yet.
            </EmptyState>
          ) : null}
          {items.length > 0 ? (
            <Table.ScrollContainer minWidth={760} className="stack-scroll">
              <StackTable className="stack-table stack-cards">
                <StackTable.Thead>
                  <StackTable.Tr>
                    <StackTable.Th>Review</StackTable.Th>
                    <StackTable.Th>Production</StackTable.Th>
                    <StackTable.Th>State</StackTable.Th>
                    <StackTable.Th>Findings</StackTable.Th>
                    <StackTable.Th>Started</StackTable.Th>
                    <StackTable.Th>Requested by</StackTable.Th>
                  </StackTable.Tr>
                </StackTable.Thead>
                <StackTable.Tbody>
                  {items.map((r) => (
                    <ReviewRow key={r.reviewId} r={r} />
                  ))}
                </StackTable.Tbody>
              </StackTable>
            </Table.ScrollContainer>
          ) : null}
        </Section>
        {reviews.data ? (
          <ApiSource endpoint="GET /api/shutter/production-reviews?limit=100" data={reviews.data} />
        ) : null}
      </Stack>
    </>
  );
}
