import { Anchor, Container, Grid, Stack } from '@mantine/core';
import { Link, useParams } from 'react-router';
import { useIncident, useIncidentEvents, useMe } from '@/api/hooks';
import type { IncidentDetail, Me } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { isApiError } from '@/lib/errors';
import { ChainsPanel } from './incident/ChainsPanel';
import { useDecideDialog } from './incident/DecideModal';
import { IncidentApprovalPanel } from './incident/IncidentApprovalPanel';
import { IncidentHeader } from './incident/IncidentHeader';
import { IncidentPlanPanel } from './incident/IncidentPlanPanel';
import { IncidentTimeline } from './incident/IncidentTimeline';

function Incident({ inc, me }: { inc: IncidentDetail; me: Me | null | undefined }) {
  const events = useIncidentEvents(inc.incidentId, inc.state !== 'closed');
  const dialog = useDecideDialog(inc);
  return (
    <>
      <IncidentHeader inc={inc} />
      <Grid gutter="md">
        <Grid.Col span={{ base: 12, xl: 8 }}>
          <Stack gap="md">
            <ChainsPanel inc={inc} me={me} onDecide={dialog.open} />
            {me ? <IncidentApprovalPanel inc={inc} me={me} onDecide={(d) => dialog.open(d)} /> : null}
            <IncidentPlanPanel inc={inc} />
          </Stack>
        </Grid.Col>
        <Grid.Col span={{ base: 12, xl: 4 }}>
          <div style={{ position: 'sticky', top: 72 }}>
            <IncidentTimeline events={events.data ?? []} />
          </div>
        </Grid.Col>
      </Grid>
      {dialog.modal}
    </>
  );
}

export default function IncidentPage() {
  const { incidentId = '' } = useParams();
  const me = useMe().data;
  const inc = useIncident(incidentId);

  if (inc.isPending) return <PageSkeleton label={`Loading incident ${incidentId}…`} />;
  if (inc.isError)
    return (
      <Container size="sm" py="xl">
        <ErrorAlert
          error={inc.error}
          title={
            isApiError(inc.error) && inc.error.isNotFound
              ? `There is no incident ${incidentId}`
              : `Incident ${incidentId} could not be read`
          }
          onRetry={isApiError(inc.error) && inc.error.isNotFound ? undefined : () => void inc.refetch()}
        />
        <Anchor component={Link} to="/incidents" size="sm" mt="sm" display="block">
          All incidents
        </Anchor>
      </Container>
    );
  return <Incident inc={inc.data} me={me} />;
}
