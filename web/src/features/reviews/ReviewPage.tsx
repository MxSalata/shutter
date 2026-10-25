import { Alert, Anchor, Badge, Container, Group, List, Loader, Stack, Text } from '@mantine/core';
import { Link, useParams } from 'react-router';
import { isReviewRunning, useMe, useReview } from '@/api/hooks';
import type { ReviewDetail } from '@/api/types';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { NotYet, Section } from '@/features/cases/case/Section';
import { isApiError } from '@/lib/errors';
import { formatDuration, formatInt, formatUsd, humanize } from '@/lib/format';
import { useAnnotationDialogs } from './AnnotationDialogs';
import { AgentStateBadge, ReviewStateBadge, SeverityCounts } from './badges';
import { FindingsTable } from './FindingsTable';
import { describeAgent, explainedLine, hl7Note, orderedFindings, rankedByAgent, READ_ONLY } from './review';

function AgentBlock({ r }: { r: ReviewDetail }) {
  const a = r.agent;
  const view = describeAgent(a, r.state);
  const ran = a.mode !== null;
  return (
    <Section
      id="agent"
      title="The agent's ranking"
      note="One AI Hub agent ranks the findings within their severity tiers and explains each against the case history. It sees names, values, counts and case ids, never an error's text, and it never changes a severity or a count."
      aside={<AgentStateBadge state={a.state} />}
    >
      <Alert color={view.colour} variant="light" title={view.title} role="note">
        <Text size="sm">{view.text}</Text>
      </Alert>
      {explainedLine(a) ? <Text size="sm">{explainedLine(a)}</Text> : null}
      {a.summary ? <Text size="sm">{a.summary}</Text> : null}
      {a.unknowns.length ? (
        <Stack gap={2}>
          <Text size="sm" fw={600}>
            What the findings do not decide
          </Text>
          <List size="sm" spacing={2}>
            {a.unknowns.map((u) => (
              <List.Item key={u}>{u}</List.Item>
            ))}
          </List>
        </Stack>
      ) : null}
      {ran ? (
        <KeyValueList
          rows={[
            ['Mode', a.mode ? humanize(a.mode) : ''],
            ['Model', a.model ?? ''],
            [
              'Tokens',
              a.promptTokens || a.completionTokens
                ? `${formatInt(a.promptTokens)} in · ${formatInt(a.completionTokens)} out`
                : '',
            ],
            [
              'Cost',
              a.mode === 'replay' ? `${formatUsd(0)} (a replay spends nothing)` : formatUsd(a.costUsd),
            ],
            ['Duration', a.durationMs ? formatDuration(a.durationMs) : ''],
            ['Record key', <Digest key="k" value={a.recordKey} label="record key" length={40} />],
          ]}
        />
      ) : null}
    </Section>
  );
}

function Review({ r }: { r: ReviewDetail }) {
  const me = useMe().data;
  const dialogs = useAnnotationDialogs(r);
  const running = isReviewRunning(r.state);
  const findings = orderedFindings(r);
  const s = r.summary;
  return (
    <>
      <PageHeader
        title={`Review ${r.reviewId}`}
        subtitle={`${r.production} in ${r.namespace}. ${READ_ONLY}`}
        actions={
          <Anchor component={Link} to="/reviews" size="sm">
            All reviews
          </Anchor>
        }
      />
      <Stack gap="md">
        {running ? (
          <Alert
            color="blue"
            variant="light"
            icon={<Loader size={16} />}
            title={humanize(r.state)}
            role="note"
          >
            <Text size="sm">
              {r.state === 'sweeping'
                ? "Reading the production's settings, its event log and its messages; this takes seconds."
                : 'The findings are stored; the agent is ranking them, which can take up to 10 minutes.'}{' '}
              This page reads the review again every 2 seconds.
            </Text>
          </Alert>
        ) : null}
        {r.state === 'failed' ? (
          <Alert color="red" variant="light" role="alert" title="The review failed">
            <Text size="sm">{r.error || 'The sweep failed.'}</Text>
          </Alert>
        ) : null}
        <Section
          id="review"
          title="The review"
          aside={<ReviewStateBadge state={r.state} />}
          note={r.unreadable ? 'The namespace could not be read: the one finding says why.' : undefined}
        >
          <KeyValueList
            rows={[
              ['Production', `${r.production} (${r.namespace})`],
              ['Production state', humanize(r.productionState)],
              [
                'Window',
                r.window ? (
                  <Text size="sm" key="w">
                    {r.window.days} {r.window.days === 1 ? 'day' : 'days'}, from{' '}
                    <Timestamp iso={r.window.from} /> to <Timestamp iso={r.window.to} />
                  </Text>
                ) : (
                  ''
                ),
              ],
              ['Started', <Timestamp key="s" iso={r.startedAt} />],
              ['Finished', r.finishedAt ? <Timestamp key="f" iso={r.finishedAt} /> : ''],
              ['Requested by', r.requestedBy],
              ['Items read', s.items !== undefined ? formatInt(s.items) : ''],
              [
                'Configuration fingerprint',
                r.fingerprint ? (
                  <Digest key="d" value={r.fingerprint} label="configuration fingerprint" />
                ) : (
                  ''
                ),
              ],
            ]}
          />
        </Section>
        <Section
          id="summary"
          title="Summary"
          note="Severity is how bad the hazard is; confidence, kept apart, is how the finding was read."
        >
          {s.bySeverity ? (
            <Stack gap="xs">
              <SeverityCounts summary={s} />
              <Group gap="lg" wrap="wrap">
                <Text size="sm">
                  {formatInt(s.findings)} {s.findings === 1 ? 'finding' : 'findings'}
                </Text>
                {s.intended ? <Text size="sm">{formatInt(s.intended)} marked by an approver</Text> : null}
                <Text size="sm">{formatInt(s.errorsInWindow)} event log errors in the window</Text>
                <Text size="sm">{formatInt(s.messageErrorsInWindow)} messages in error in the window</Text>
              </Group>
            </Stack>
          ) : r.state === 'failed' ? (
            <Text size="sm">
              There is no result because the review failed{r.error ? `: ${r.error}` : '.'}
            </Text>
          ) : (
            <NotYet>Not yet: the sweep is still reading.</NotYet>
          )}
        </Section>
        <AgentBlock r={r} />
        <Section
          id="findings"
          title="Findings"
          note={
            rankedByAgent(r)
              ? "In the agent's order: within each severity tier, as it ranked them."
              : 'In the deterministic order: severity tier, then unique cases, then the most recent evidence.'
          }
          aside={
            <Badge variant="light" color="gray" style={{ textTransform: 'none' }}>
              {findings.length}
            </Badge>
          }
        >
          {hl7Note(r) ? (
            <Text size="sm" c="dimmed">
              {hl7Note(r)}
            </Text>
          ) : null}
          {findings.length ? (
            <FindingsTable
              findings={findings}
              namespace={r.namespace}
              approver={!!me?.approver}
              onMark={dialogs.mark}
              onUnmark={dialogs.unmark}
            />
          ) : (
            <NotYet>
              {running
                ? 'Not yet: the sweep is still reading.'
                : r.state === 'failed'
                  ? 'No findings: the review failed.'
                  : 'No findings.'}
            </NotYet>
          )}
        </Section>
      </Stack>
      {dialogs.modals}
    </>
  );
}

export default function ReviewPage() {
  const { reviewId = '' } = useParams();
  const review = useReview(reviewId);

  if (review.isPending) return <PageSkeleton label={`Loading review ${reviewId}…`} />;
  if (review.isError)
    return (
      <Container size="sm" py="xl">
        <ErrorAlert
          error={review.error}
          title={
            isApiError(review.error) && review.error.isNotFound
              ? `There is no review ${reviewId}`
              : `Review ${reviewId} could not be read`
          }
          onRetry={
            isApiError(review.error) && review.error.isNotFound ? undefined : () => void review.refetch()
          }
        />
        <Anchor component={Link} to="/reviews" size="sm" mt="sm" display="block">
          All reviews
        </Anchor>
      </Container>
    );
  return <Review r={review.data} />;
}
