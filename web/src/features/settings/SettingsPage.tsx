import { Badge, Group, Stack } from '@mantine/core';
import { IconSettings } from '@tabler/icons-react';
import { useCosts, useSettings } from '@/api/hooks';
import type { Settings } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { AgentsSection } from './AgentsSection';
import { CostsSection } from './CostsSection';
import { PricesSection } from './PricesSection';
import { SettingsTiles } from './SettingsTiles';

function Flag({ children }: { children: React.ReactNode }) {
  return (
    <Badge color="gray" variant="outline" style={{ textTransform: 'none' }}>
      {children}
    </Badge>
  );
}

/** What the instance has, as small badges under the figures: the demo instance, the API mimic, AI Hub, the runner, a provider. */
function Flags({ s }: { s: Settings }) {
  const flags = [
    s.demo && 'Demo instance',
    s.mock && `API mimic on${s.mockConfig ? ` (${s.mockConfig})` : ''}`,
    s.aiHubPresent && 'AI Hub present',
    s.liveRunnerPresent && 'AI Hub runner installed',
    s.providerConfigured && 'Model provider configured',
  ].filter(Boolean) as string[];
  if (!flags.length) return null;
  return (
    <Group gap="xs" wrap="wrap">
      {flags.map((f) => (
        <Flag key={f}>{f}</Flag>
      ))}
    </Group>
  );
}

export default function SettingsPage() {
  const settings = useSettings();
  const costs = useCosts();
  const s = settings.data;
  const loading = settings.isPending || costs.isPending;
  return (
    <>
      <PageHeader
        title="Settings and costs"
        icon={IconSettings}
        hue="cyan"
        lead="How the agents answer, the prices used for costs, and what was spent."
        details="Read from the production and the store. Agent items are changed in the production's settings."
      />
      <Stack gap="md">
        {loading ? <PageSkeleton label="Loading the settings…" /> : null}
        {settings.isError ? (
          <ErrorAlert
            error={settings.error}
            title="The settings could not be read"
            onRetry={() => void settings.refetch()}
          />
        ) : null}
        {loading ? null : (
          <>
            <SettingsTiles s={s} costs={costs.data} />
            {s ? <Flags s={s} /> : null}
            {s ? <AgentsSection s={s} /> : null}
            <CostsSection costs={costs} settings={s} />
            {s ? <PricesSection prices={s.prices} /> : null}
            <Stack gap="xs">
              {s ? (
                <ApiSource
                  endpoint="GET /api/shutter/settings"
                  data={s}
                  label="Settings, as the API sends it"
                />
              ) : null}
              {costs.data ? (
                <ApiSource
                  endpoint="GET /api/shutter/costs"
                  data={costs.data}
                  label="Costs, as the API sends it"
                />
              ) : null}
            </Stack>
          </>
        )}
      </Stack>
    </>
  );
}
