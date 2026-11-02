import { Anchor, List, Stack, Text, VisuallyHidden } from '@mantine/core';
import { IconHeartbeat } from '@tabler/icons-react';
import { useHealth } from '@/api/hooks';
import { ApiSource } from '@/components/ApiSource';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { TechDetail } from '@/components/TechDetail';
import { TRIAL } from '@/env/mode';
import { PROOF } from '@/lib/proof';
import { HealthGroup } from './HealthGroup';
import { HealthHero } from './HealthHero';
import { agentsBadge, groupReport, provenanceFacts, type Group, type Report } from './report';
import './health.css';

/** A group link scrolls to the group's heading and moves focus to it (the hash belongs to the router). */
function jumpTo(group: Group) {
  const target = document.getElementById(`health-${group.def.id}-title`);
  target?.scrollIntoView?.({ block: 'start' });
  target?.focus({ preventScroll: true });
}

/** One line of links to the groups, each with its count where the group has checks: no tiles that repeat the groups. */
function GroupLinks({ groups }: { groups: Group[] }) {
  return (
    <nav aria-label="Groups">
      <ul className="health-links" role="list">
        {groups.map((g) => {
          const counted = g.checks.length
            ? ` ${g.checks.filter((c) => c.passed).length} of ${g.checks.length}`
            : '';
          return (
            <li key={g.def.id}>
              <Anchor component="button" type="button" size="sm" onClick={() => jumpTo(g)}>
                {g.def.title}
                {counted}
                {counted ? <VisuallyHidden> pass</VisuallyHidden> : null}
              </Anchor>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

export default function HealthPage() {
  const health = useHealth();
  const report: Report | null =
    health.data && typeof health.data === 'object' ? (health.data as Report) : null;
  if (health.isPending) return <PageSkeleton label="Checking…" shape="detail" />;
  const { verdict, groups } = report ? groupReport(report, TRIAL) : { verdict: null, groups: [] };
  const facts = report ? provenanceFacts(report.recorded) : [];
  const replays = report ? agentsBadge(report, TRIAL, PROOF.recordedOn)?.kind === 'recorded' : false;
  return (
    <>
      <PageHeader
        tour="health"
        icon={IconHeartbeat}
        hue="indigo"
        title="Health"
        lead="The installation checks itself: its message engine, web pages, agents and licence."
        details="The installation's own readiness report: namespace, production, web applications, downstream system, knowledge and agents."
      />
      {health.isError ? (
        <ErrorAlert
          error={health.error}
          title="The readiness report could not be read"
          onRetry={() => void health.refetch()}
        />
      ) : null}
      {report && verdict ? (
        <Stack gap="md">
          <Stack gap="sm">
            <HealthHero report={report} verdict={verdict} trial={TRIAL} recordedOn={PROOF.recordedOn} />
            <GroupLinks groups={groups} />
            {TRIAL ? (
              <Text size="sm" c="dimmed" maw="68ch">
                This is the report of the instance the trial was recorded on. Parts it did not have say so.
              </Text>
            ) : null}
          </Stack>
          {groups.map((g) => (
            <HealthGroup
              key={g.def.id}
              group={g}
              report={report}
              intro={
                TRIAL && replays && g.def.id === 'agents'
                  ? "The agents' runs were recorded on IRIS AI Hub; this report's instance replays them."
                  : undefined
              }
            />
          ))}
          {facts.length ? (
            <TechDetail label="Where this report comes from" kind="explain">
              <List spacing={4} size="sm">
                {facts.map((f) => (
                  <List.Item key={f}>{f}</List.Item>
                ))}
              </List>
            </TechDetail>
          ) : null}
          <ApiSource
            endpoint="GET /api/shutter/health"
            data={report}
            label="The report as the API sends it"
          />
        </Stack>
      ) : null}
    </>
  );
}
