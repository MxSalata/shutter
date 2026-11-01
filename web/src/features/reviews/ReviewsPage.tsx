import {
  Alert,
  Anchor,
  Badge,
  Button,
  Group,
  NativeSelect,
  NumberInput,
  Stack,
  Switch,
  Table,
  Text,
} from '@mantine/core';
import { IconClipboardSearch } from '@tabler/icons-react';
import { useState } from 'react';
import { Link, useNavigate } from 'react-router';
import { newIdempotencyKey } from '@/api/client';
import { useMe, useReviews, useReviewTargets, useStartReview } from '@/api/hooks';
import type { ReviewListItem, ReviewTarget } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { Section } from '@/components/Section';
import { describeError, isApiError } from '@/lib/errors';
import { AgentStateBadge, ReviewStateBadge, SeverityCounts } from './badges';
import { READ_ONLY, targetKey, targetLabel } from './review';

/** What a 409 wrong_state carries besides its detail: the review of that production still running. */
interface Running {
  reviewId?: string;
  state?: string;
}

function StartReview({ targets }: { targets: ReviewTarget[] }) {
  const navigate = useNavigate();
  const start = useStartReview();
  const [target, setTarget] = useState(() =>
    targets.find((t) => t.own) ? targetKey(targets.find((t) => t.own)!) : '',
  );
  const [days, setDays] = useState<number | string>(7);
  const [agent, setAgent] = useState(true);
  const chosen = targets.find((t) => targetKey(t) === target) ?? targets[0];
  const windowDays = Number(days);
  const windowOk = Number.isInteger(windowDays) && windowDays >= 1 && windowDays <= 90;
  const submit = () => {
    if (!chosen || !windowOk) return;
    start.mutate(
      {
        target: { namespace: chosen.namespace, production: chosen.production, windowDays, agent },
        idempotencyKey: newIdempotencyKey(),
      },
      { onSuccess: (r) => navigate(`/reviews/${encodeURIComponent(r.reviewId)}`) },
    );
  };
  const running =
    isApiError(start.error) && start.error.code === 'wrong_state'
      ? (start.error.body as Running | null)
      : null;
  return (
    <Stack gap="sm">
      <Group gap="sm" align="flex-end" wrap="wrap">
        <NativeSelect
          label="Production"
          value={chosen ? targetKey(chosen) : ''}
          onChange={(e) => setTarget(e.currentTarget.value)}
          data={targets.map((t) => ({ value: targetKey(t), label: targetLabel(t) }))}
          w={{ base: '100%', sm: 360 }}
        />
        <NumberInput
          label="Window (days)"
          value={days}
          onChange={setDays}
          min={1}
          max={90}
          allowDecimal={false}
          error={windowOk ? undefined : 'From 1 to 90 days'}
          w={140}
        />
      </Group>
      <Switch
        label="Ask the agent to rank and explain the findings"
        description="It reorders within a severity tier only. A live run spends model credit, as a scenario run does; an instance without a model provider replays a recorded run."
        checked={agent}
        onChange={(e) => setAgent(e.currentTarget.checked)}
      />
      {chosen && chosen.productionState !== 'running' ? (
        <Text size="sm" c="dimmed">
          {chosen.production} is {chosen.productionState}: the review still reads its configuration.
        </Text>
      ) : null}
      {start.error ? (
        <Alert color="red" variant="light" role="alert" title="The review did not start">
          <Text size="sm">{describeError(start.error)}</Text>
          {running?.reviewId ? (
            <Anchor component={Link} to={`/reviews/${encodeURIComponent(running.reviewId)}`} size="sm">
              Follow review {running.reviewId}
            </Anchor>
          ) : null}
        </Alert>
      ) : null}
      <Group>
        <Button
          leftSection={<IconClipboardSearch size={16} />}
          onClick={submit}
          loading={start.isPending}
          disabled={!chosen || !windowOk}
        >
          Start the review
        </Button>
      </Group>
    </Stack>
  );
}

function ReviewRow({ r }: { r: ReviewListItem }) {
  return (
    <Table.Tr>
      <Table.Td>
        <Anchor component={Link} to={`/reviews/${encodeURIComponent(r.reviewId)}`} fw={600} size="sm">
          {r.reviewId}
        </Anchor>
      </Table.Td>
      <Table.Td>
        <Text size="sm">{r.production}</Text>
        <Text size="xs" c="dimmed">
          {r.namespace}
        </Text>
      </Table.Td>
      <Table.Td>
        <Group gap={4} wrap="wrap">
          <ReviewStateBadge state={r.state} />
          <AgentStateBadge state={r.agentState} />
        </Group>
      </Table.Td>
      <Table.Td>
        <SeverityCounts summary={r.summary} />
      </Table.Td>
      <Table.Td>
        <Timestamp iso={r.startedAt} age />
      </Table.Td>
      <Table.Td>
        <Text size="sm">{r.requestedBy}</Text>
      </Table.Td>
    </Table.Tr>
  );
}

export default function ReviewsPage() {
  const me = useMe().data;
  const targets = useReviewTargets();
  const reviews = useReviews({ limit: 100 });
  return (
    <>
      <PageHeader
        title="Production review"
        subtitle={`One read-only pass over a production Shutter runs or watches: the effective value of the settings that decide whether a failure is retried, seen and kept in order, the message purge task, and the window's errors and failed messages, each tied to the cases Shutter opened. ${READ_ONLY}`}
      />
      <Stack gap="md">
        <Section
          id="start"
          tour="reviews-start"
          title="Start a review"
          note="Shutter's own production, or a watched one its cases came from. The checks are deterministic; the agent only ranks and explains."
        >
          {TRIAL ? (
            <Text size="sm">
              The online demo shows the recorded reviews of both productions below. On an instance an operator
              starts a review here.
            </Text>
          ) : !me?.operator ? (
            <Text size="sm" c="dimmed">
              An operator starts a review.
            </Text>
          ) : targets.isPending ? (
            <PageSkeleton label="Loading the productions…" />
          ) : targets.isError ? (
            <ErrorAlert
              error={targets.error}
              title="The productions could not be read"
              onRetry={() => void targets.refetch()}
            />
          ) : targets.data.items.length === 0 ? (
            <Text size="sm" c="dimmed">
              No production to review.
            </Text>
          ) : (
            <StartReview targets={targets.data.items} />
          )}
        </Section>
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
          {reviews.data && reviews.data.items.length === 0 ? (
            <Text c="dimmed" size="sm" py="md">
              No reviews yet.
            </Text>
          ) : null}
          {reviews.data && reviews.data.items.length > 0 ? (
            <Table.ScrollContainer minWidth={760}>
              <Table>
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Review</Table.Th>
                    <Table.Th>Production</Table.Th>
                    <Table.Th>State</Table.Th>
                    <Table.Th>Findings</Table.Th>
                    <Table.Th>Started</Table.Th>
                    <Table.Th>Requested by</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {reviews.data.items.map((r) => (
                    <ReviewRow key={r.reviewId} r={r} />
                  ))}
                </Table.Tbody>
              </Table>
            </Table.ScrollContainer>
          ) : null}
        </Section>
      </Stack>
    </>
  );
}
