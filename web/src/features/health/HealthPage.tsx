import { Card } from '@mantine/core';
import { useHealth } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { JsonBlock } from '@/components/JsonBlock';

export default function HealthPage() {
  const health = useHealth();
  return (
    <>
      <PageHeader
        title="Health"
        subtitle="The installation's own readiness report: namespace, production, web applications, ward system, knowledge and agents."
      />
      <Card padding="md">
        {health.isPending ? <PageSkeleton label="Checking…" /> : null}
        {health.isError ? (
          <ErrorAlert
            error={health.error}
            title="The readiness report could not be read"
            onRetry={() => void health.refetch()}
          />
        ) : null}
        {health.data ? <JsonBlock value={health.data} label="readiness report" /> : null}
      </Card>
    </>
  );
}
