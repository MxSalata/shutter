import { Anchor, Container, Grid, Stack } from '@mantine/core';
import { useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
import { isOpen, keys, useApprovals, useCase, useCaseEvents, useMe, usePlan } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { isApiError } from '@/lib/errors';
import { CaseHeader } from './case/CaseHeader';
import { Lifecycle } from './case/Lifecycle';
import { FailurePanel } from './case/FailurePanel';
import { EvidencePanel } from './case/EvidencePanel';
import { BoardPanel } from './case/BoardPanel';
import { PlanPanel, RehearsalPanel } from './case/PlanPanel';
import { ApprovalPanel } from './case/ApprovalPanel';
import { ExecutionPanel } from './case/ExecutionPanel';
import { OutcomePanel } from './case/OutcomePanel';
import { EscalationPanel } from './case/EscalationPanel';
import { AbandonPanel } from './case/AbandonPanel';
import { CaseTimeline } from './case/CaseTimeline';
import { ReceiptCard } from './case/ReceiptCard';
import { S8Compare } from './case/S8Compare';

/** The portal's base path (/csp/<namespace>/) for links to messages, read from the case's trace link. */
function portalBase(visualTrace: string | undefined): string {
  const m = visualTrace ? /^(.*\/)EnsPortal\./.exec(visualTrace) : null;
  return m ? m[1] : '/csp/shutter/';
}

export default function CasePage() {
  const { caseId = '' } = useParams();
  const [search] = useSearchParams();
  const me = useMe().data;
  const c = useCase(caseId);
  const open = isOpen(c.data?.state);
  const events = useCaseEvents(caseId, open);
  const plan = usePlan(caseId, open);
  const approvals = useApprovals(caseId, open);
  const client = useQueryClient();
  // The parts poll only while the case is open: when it closes, fetch them once more so the last events show.
  const wasOpen = useRef(open);
  useEffect(() => {
    if (wasOpen.current && !open) void client.invalidateQueries({ queryKey: keys.case(caseId) });
    wasOpen.current = open;
  }, [open, caseId, client]);

  if (c.isPending) return <PageSkeleton label={`Loading case ${caseId}…`} />;
  if (c.isError)
    return (
      <Container size="sm" py="xl">
        <ErrorAlert
          error={c.error}
          title={
            isApiError(c.error) && c.error.isNotFound
              ? `There is no case ${caseId}`
              : `Case ${caseId} could not be read`
          }
          onRetry={isApiError(c.error) && c.error.isNotFound ? undefined : () => void c.refetch()}
        />
        <Anchor component={Link} to="/cases" size="sm" mt="sm" display="block">
          All cases
        </Anchor>
      </Container>
    );

  const detail = c.data;
  const write = plan.data?.plan?.disposition === 'resend';
  return (
    <>
      <CaseHeader c={detail} />
      <Lifecycle c={detail} events={events.data ?? []} />
      <Grid gutter="md">
        <Grid.Col span={{ base: 12, xl: 8 }}>
          <Stack gap="md">
            <ReceiptCard c={detail} open={open} />
            <OutcomePanel c={detail} />
            {/* The board's findings right under the outcome: what the case was decided on, before how it got there */}
            <BoardPanel
              caseId={caseId}
              open={open}
              mode={detail.mode}
              withheld={detail.failureKind === 'withheld'}
              portalBase={portalBase(detail.links?.visualTrace)}
            />
            {detail.scenario === 'S8' ? (
              <S8Compare caseId={caseId} focus={search.get('show') === 'compare'} />
            ) : null}
            <EscalationPanel c={detail} />
            <AbandonPanel c={detail} events={events.data} />
            <FailurePanel c={detail} />
            <EvidencePanel caseId={caseId} open={open} />
            <PlanPanel view={plan.data} loading={plan.isPending} />
            <RehearsalPanel view={plan.data} write={write} />
            {me ? <ApprovalPanel c={detail} me={me} view={plan.data} approvals={approvals.data} /> : null}
            <ExecutionPanel caseId={caseId} open={open} write={write} />
          </Stack>
        </Grid.Col>
        <Grid.Col span={{ base: 12, xl: 4 }}>
          <div style={{ position: 'sticky', top: 72 }}>
            <CaseTimeline events={events.data ?? []} />
          </div>
        </Grid.Col>
      </Grid>
    </>
  );
}
