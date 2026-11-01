import {
  Alert,
  Anchor,
  Badge,
  Container,
  List,
  Loader,
  Paper,
  Progress,
  SimpleGrid,
  Stack,
  Text,
} from '@mantine/core';
import { IconEye } from '@tabler/icons-react';
import { Link, useParams } from 'react-router';
import { DEMO_READ_ONLY, readOnlyDemo } from '@/api/can';
import { isReviewRunning, useCan, useReview } from '@/api/hooks';
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
import { AgentStateBadge, ReviewStateBadge } from './badges';
import { FindingCards } from './FindingCards';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { SEVERITY_STATUS } from '@/lib/status';
import {
  describeAgent,
  explainedCount,
  explainedNotes,
  hl7Note,
  orderedFindings,
  rankedByAgent,
  READ_ONLY,
  SEVERITIES,
} from './review';

/**
 * "2 of 9 findings explained", with a bar: the server's own counts when the agent answered, else the findings that
 * carry an explanation, so a review with no recorded explanation says 0 of 9 rather than nothing.
 */
function Explained({ r }: { r: ReviewDetail }) {
  if (r.state !== 'done' || !r.findings.length) return null;
  const { explained, total } = explainedCount(r);
  return (
    <Stack gap={4}>
      <Text size="sm" fw={600}>
        {`${explained} of ${total} ${total === 1 ? 'finding' : 'findings'} explained by the agent`}
      </Text>
      <Progress
        value={total ? (explained / total) * 100 : 0}
        size="sm"
        maw={420}
        aria-label={`${explained} of ${total} findings explained by the agent`}
      />
      {explainedNotes(r.agent) || explained < total ? (
        <Text size="xs" c="dimmed">
          {[
            explainedNotes(r.agent),
            explained < total ? 'A finding with no explanation shows the deterministic text only.' : '',
          ]
            .filter(Boolean)
            .join(' ')}
        </Text>
      ) : null}
    </Stack>
  );
}

/** The review's counts as a row of tiles: the findings, each severity with findings, the errors in the window. */
function Counts({ r }: { r: ReviewDetail }) {
  const s = r.summary;
  if (!s.bySeverity) return null;
  const tiles: { key: string; figure: string; label: React.ReactNode }[] = [
    { key: 'findings', figure: formatInt(s.findings), label: s.findings === 1 ? 'finding' : 'findings' },
    ...SEVERITIES.filter((sev) => (s.bySeverity?.[sev] ?? 0) > 0).map((sev) => ({
      key: sev,
      figure: formatInt(s.bySeverity![sev]),
      label: <StatusBadge {...SEVERITY_STATUS[sev]} size="sm" />,
    })),
    { key: 'errors', figure: formatInt(s.errorsInWindow), label: 'event log errors in the window' },
    {
      key: 'messages',
      figure: formatInt(s.messageErrorsInWindow),
      label: 'messages in error in the window',
    },
    ...(s.intended ? [{ key: 'marked', figure: formatInt(s.intended), label: 'marked by an approver' }] : []),
  ];
  return (
    <SimpleGrid cols={{ base: 2, sm: 3, lg: tiles.length }} spacing="xs">
      {tiles.map((t) => (
        <Paper key={t.key} withBorder p="sm" radius="md">
          <Text fz={24} fw={700} lh={1.1} className="tabular">
            {t.figure}
          </Text>
          {typeof t.label === 'string' ? <Text size="xs">{t.label}</Text> : t.label}
        </Paper>
      ))}
    </SimpleGrid>
  );
}

function AgentBlock({ r }: { r: ReviewDetail }) {
  const a = r.agent;
  const view = describeAgent(a, r.state);
  const ran = a.mode !== null;
  return (
    <Section
      id="agent"
      tour="review-agent"
      title="The agent's ranking"
      note="One AI Hub agent ranks the findings within their severity tiers and explains each against the case history. It sees names, values, counts and case ids, never an error's text, and it never changes a severity or a count."
      aside={<AgentStateBadge state={a.state} />}
    >
      <Alert color={view.colour} variant="light" title={view.title} role="note">
        <Text size="sm">{view.text}</Text>
      </Alert>
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
  // Annotating a finding changes what the site records about its production: the configure resource's
  const can = useCan();
  const canAnnotate = can.configure;
  const dialogs = useAnnotationDialogs(r);
  const running = isReviewRunning(r.state);
  const findings = orderedFindings(r);
  const s = r.summary;
  return (
    <>
      <PageHeader
        title={`Review ${r.reviewId}`}
        subtitle={`${r.production} in ${r.namespace}${r.window ? `, ${r.window.days} ${r.window.days === 1 ? 'day' : 'days'} of history` : ''}.`}
        actions={
          <>
            <ReviewStateBadge state={r.state} />
            <Anchor component={Link} to="/reviews" size="sm">
              All reviews
            </Anchor>
          </>
        }
      />
      <Stack gap="md">
        <StatusNotice tone="info" role="note" icon={IconEye} title="Read only">
          <Text size="sm">{READ_ONLY}</Text>
        </StatusNotice>
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
          id="summary"
          title="Summary"
          note="Severity is how bad the hazard is; confidence, kept apart, is how the finding was read."
        >
          {s.bySeverity ? (
            <Counts r={r} />
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
          tour="review-findings"
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
          {readOnlyDemo(can) ? (
            <Text size="sm" c="dimmed" data-testid="demo-read-only">
              {DEMO_READ_ONLY}, annotations included.
            </Text>
          ) : null}
          {/* How many of these the agent explained, stated once, directly above the cards */}
          <Explained r={r} />
          {findings.length ? (
            <FindingCards
              findings={findings}
              recorded={r.agent.mode === 'replay'}
              namespace={r.namespace}
              canAnnotate={canAnnotate}
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
        <Section
          id="review"
          title="About this review"
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
