import { Alert, Anchor, Container, Loader, Stack, Text } from '@mantine/core';
import { IconClipboardSearch, IconEye } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { DEMO_READ_ONLY, readOnlyDemo } from '@/api/can';
import { isReviewRunning, useCan, useReview } from '@/api/hooks';
import type { ReviewDetail, Severity } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { NotYet, Section } from '@/components/Section';
import { StatTile } from '@/components/StatTile';
import { StatusNotice } from '@/components/StatusBadge';
import { SummaryBand } from '@/components/SummaryBand';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { isApiError } from '@/lib/errors';
import { formatInt, humanize } from '@/lib/format';
import { SEVERITY_STATUS } from '@/lib/status';
import { AgentBlock } from './AgentBlock';
import { useAnnotationDialogs } from './AnnotationDialogs';
import { ReviewStateBadge, SeverityBadge } from './badges';
import { FindingCards } from './FindingCards';
import { agentLeads, hl7Note, orderedFindings, rankedByAgent, READ_ONLY, SEVERITIES } from './review';

/** "0 high · 1 marked": the tiers with no findings, which get no tile of their own (F19), and the findings marked. */
function findingsCaption(r: ReviewDetail): string {
  const s = r.summary;
  if (!s.findings) return 'No findings';
  const zero = (['high', 'medium', 'low'] as Severity[])
    .filter((sev) => (s.bySeverity?.[sev] ?? 0) === 0)
    .map((sev) => `0 ${sev}`);
  return [...zero, ...(s.intended ? [`${formatInt(s.intended)} marked`] : [])].join(' · ');
}

/**
 * The review's counts as a row of tiles: one for each severity that has findings, the findings (with the tiers that
 * have none and the marks in its caption), the errors logged and the messages in error. Never a tile for a zero.
 */
function Counts({ r }: { r: ReviewDetail }) {
  const s = r.summary;
  if (!s.bySeverity)
    return (
      <section aria-label="Summary">
        {r.state === 'failed' ? (
          <Text size="sm">There is no result because the review failed{r.error ? `: ${r.error}` : '.'}</Text>
        ) : (
          <NotYet>Not yet: the sweep is still reading.</NotYet>
        )}
      </section>
    );
  const tiers = SEVERITIES.filter((sev) => (s.bySeverity?.[sev] ?? 0) > 0);
  const tiles: ReactNode[] = [
    ...tiers.map((sev) => (
      <StatTile
        key={sev}
        label="Severity"
        figure={formatInt(s.bySeverity![sev])}
        tone={SEVERITY_STATUS[sev].tone}
        status={<SeverityBadge severity={sev} />}
      />
    )),
    <StatTile key="findings" label="Findings" figure={formatInt(s.findings)} caption={findingsCaption(r)} />,
    <StatTile
      key="errors"
      label="Errors logged"
      figure={formatInt(s.errorsInWindow)}
      caption="in the window"
    />,
    <StatTile
      key="messages"
      label="Messages in error"
      figure={formatInt(s.messageErrorsInWindow)}
      caption="in the window"
    />,
  ];
  return (
    <SummaryBand title="Summary" cols={{ base: 2, sm: 3, lg: Math.min(tiles.length, 5) }}>
      {tiles}
    </SummaryBand>
  );
}

function Review({ r }: { r: ReviewDetail }) {
  // Annotating a finding changes what the site records about its production: the configure resource's
  const can = useCan();
  const canAnnotate = can.configure;
  const dialogs = useAnnotationDialogs(r);
  const [params] = useSearchParams();
  const running = isReviewRunning(r.state);
  const findings = orderedFindings(r);
  const opened = params.get('finding');
  const agentFirst = agentLeads(r);
  const agent = <AgentBlock r={r} />;
  return (
    <>
      <PageHeader
        title={`Review ${r.reviewId}`}
        icon={IconClipboardSearch}
        hue="violet"
        status={<ReviewStateBadge state={r.state} />}
        lead={`${r.production} in ${r.namespace}${r.window ? `, ${r.window.days} ${r.window.days === 1 ? 'day' : 'days'} of history` : ''}.`}
        actions={
          <Anchor component={Link} to="/reviews" size="sm">
            All reviews
          </Anchor>
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
        <Counts r={r} />
        {agentFirst ? agent : null}
        <Section
          id="findings"
          tour="review-findings"
          title="Findings"
          note={
            rankedByAgent(r)
              ? "In the agent's order: within each severity tier, as it ranked them."
              : 'In order: severity, then unique cases, then the newest evidence.'
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
          {findings.length ? (
            <FindingCards
              findings={findings}
              recorded={r.agent.mode === 'replay'}
              namespace={r.namespace}
              canAnnotate={canAnnotate}
              onMark={dialogs.mark}
              onUnmark={dialogs.unmark}
              initialOpen={opened && findings.some((f) => f.id === opened) ? [opened] : []}
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
        {agentFirst ? null : agent}
        <Section
          id="review"
          title="About this review"
          note={r.unreadable ? 'The namespace could not be read: the one finding says why.' : undefined}
        >
          <TechDetail label="Production, window and fingerprint" kind="data">
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
                ['Items read', r.summary.items !== undefined ? formatInt(r.summary.items) : ''],
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
          </TechDetail>
        </Section>
        <ApiSource endpoint={`GET /api/shutter/production-reviews/${r.reviewId}`} data={r} />
      </Stack>
      {dialogs.modals}
    </>
  );
}

export default function ReviewPage() {
  const { reviewId = '' } = useParams();
  const review = useReview(reviewId);

  if (review.isPending) return <PageSkeleton label={`Loading review ${reviewId}…`} shape="detail" />;
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
