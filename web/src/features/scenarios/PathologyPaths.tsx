import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  Loader,
  Stack,
  Text,
  Title,
  Tooltip,
} from '@mantine/core';
import { IconPlayerPlay } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { PathologyPath, ScenarioRun } from '@/api/types';
import { StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { formatAge } from '@/lib/format';
import type { Tone } from '@/lib/tone';
import { PATHOLOGY_ANCHOR, PATHOLOGY_WORDS } from './pathologyText';

/** Where a scroll to the group lands: below the app's fixed header, with a little room. */
const LANDING_MARGIN = 'calc(var(--app-shell-header-height, 0px) + var(--mantine-spacing-md))';

const OUTAGE_TONE: Record<string, Tone> = {
  open: 'blocking',
  draining: 'info',
  closing: 'info',
  offered: 'attention',
  sending: 'info',
  needs_person: 'attention',
  paused: 'neutral',
  closed: 'neutral',
};

const outageOpen = (p: PathologyPath) => !!p.latestOutage && p.latestOutage.state !== 'closed';

/** The latest result of a path: its case, and for the outage path its outage on the Incidents page. */
function Latest({ p }: { p: PathologyPath }) {
  if (!p.latestCase && !p.latestOutage)
    return (
      <Text size="sm" c="dimmed">
        {PATHOLOGY_WORDS.notPlayed}
      </Text>
    );
  return (
    <Stack gap={4} align="flex-start">
      {p.latestOutage ? (
        <Group gap={8} wrap="wrap" align="center" data-testid={`pathology-${p.id}-outage`}>
          <Anchor component={Link} to={`/incidents#outage-${p.latestOutage.id}`} size="sm" fw={600}>
            Outage {p.latestOutage.id} on Incidents
          </Anchor>
          <StatusBadge
            tone={OUTAGE_TONE[p.latestOutage.state] ?? 'neutral'}
            label={p.latestOutage.state.replace(/_/g, ' ')}
            focusable={false}
          />
        </Group>
      ) : null}
      {p.latestCase && !p.latestOutage ? (
        <Group gap={8} wrap="wrap" align="center" data-testid={`pathology-${p.id}-case`}>
          <Anchor
            component={Link}
            to={`/cases/${encodeURIComponent(p.latestCase.caseId)}`}
            size="sm"
            fw={600}
          >
            {p.latestCase.caseId}
          </Anchor>
          <StateBadge state={p.latestCase.state} focusable={false} />
        </Group>
      ) : null}
      {outageOpen(p) ? (
        <Text size="sm" c="dimmed">
          {PATHOLOGY_WORDS.outageOpen}
        </Text>
      ) : null}
    </Stack>
  );
}

/**
 * The group under "Every scenario". `why` says why Run is unavailable now, or is "" when it is; a path whose outage is
 * still open says so on its own button, as the server would refuse it.
 */
export function PathologyPaths({
  paths,
  why,
  starting,
  onRun,
}: {
  paths: PathologyPath[];
  why: string;
  starting: (p: PathologyPath) => boolean;
  onRun: (p: PathologyPath) => void;
}) {
  return (
    <Card
      padding="md"
      component="section"
      id={PATHOLOGY_ANCHOR}
      style={{ scrollMarginTop: LANDING_MARGIN }}
      aria-labelledby="pathology-title"
      data-testid="pathology-paths"
    >
      <Stack gap="sm">
        <Title order={2} id="pathology-title">
          {PATHOLOGY_WORDS.title}
        </Title>
        <Text size="sm" maw="68ch">
          {PATHOLOGY_WORDS.lead}
        </Text>
        {paths.map((p) => {
          const own =
            p.steps.some((s) => s.wait_for_outage) && outageOpen(p) ? PATHOLOGY_WORDS.outageOpen : '';
          const blocked = why || own;
          return (
            <Card
              key={p.id}
              withBorder
              padding="sm"
              component="article"
              aria-labelledby={`pathology-${p.id}`}
            >
              <Stack gap={6}>
                <Group gap="xs" justify="space-between" wrap="wrap" align="center">
                  <Group gap="xs" wrap="nowrap" align="center">
                    <Badge variant="light" color="gray" radius="sm" style={{ flex: 'none' }}>
                      {p.id}
                    </Badge>
                    <Title order={3} fz="md" id={`pathology-${p.id}`}>
                      {p.title}
                    </Title>
                  </Group>
                  <Tooltip label={blocked} disabled={!blocked} multiline maw={260}>
                    <span>
                      <Button
                        size="xs"
                        mih={36}
                        leftSection={<IconPlayerPlay size={14} />}
                        disabled={!!blocked}
                        loading={starting(p)}
                        onClick={() => onRun(p)}
                      >
                        Run {p.id}
                      </Button>
                    </span>
                  </Tooltip>
                </Group>
                <Text size="sm" maw="68ch">
                  {p.summary}
                </Text>
                <Latest p={p} />
              </Stack>
            </Card>
          );
        })}
      </Stack>
    </Card>
  );
}

/**
 * The optional link after the main route's three cards, to the group: shown only where the server lists the paths. It
 * scrolls to the group rather than changing the address, whose hash the build IRIS serves routes by.
 */
export function PathologyLink() {
  return (
    <Text size="sm">
      <Anchor
        component="button"
        type="button"
        onClick={() => document.getElementById(PATHOLOGY_ANCHOR)?.scrollIntoView({ block: 'start' })}
      >
        {PATHOLOGY_WORDS.link}
      </Anchor>
    </Text>
  );
}

/** A pathology run's banner: what it is doing, that no agent runs, and where its result is once it has played. */
export function PathologyRunBanner({ run, path }: { run: ScenarioRun; path: PathologyPath | undefined }) {
  if (run.state === 'queued' || run.state === 'running')
    return (
      <Alert
        color="blue"
        variant="light"
        icon={<Loader size={16} />}
        title={run.state === 'queued' ? `${run.scenario} is queued` : `Playing ${run.scenario}`}
      >
        <Stack gap={6}>
          <Text size="sm">
            {run.step ? `Now ${run.step}.` : 'Starting.'} Results delivered so far:{' '}
            {run.files.length ? run.files.join(', ') : 'none'}.
          </Text>
          <Text size="sm">{PATHOLOGY_WORDS.noAgent}</Text>
        </Stack>
      </Alert>
    );
  if (run.state === 'done')
    return (
      <Alert color="blue" variant="light" title={`${run.scenario} played, ${formatAge(run.finishedAt)}`}>
        <Stack gap="xs">
          <Text size="sm">
            Delivered {run.files.join(', ') || 'no results'}. {PATHOLOGY_WORDS.noAgent}
            {run.timeouts.length ? ` It did not reach ${run.timeouts.join(', ')} in time.` : ''}
          </Text>
          {path?.latestOutage ? (
            <Button component={Link} to={`/incidents#outage-${path.latestOutage.id}`} size="xs">
              Open its outage on Incidents
            </Button>
          ) : path?.latestCase ? (
            <Button component={Link} to={`/cases/${encodeURIComponent(path.latestCase.caseId)}`} size="xs">
              Open its case, {path.latestCase.caseId}
            </Button>
          ) : null}
        </Stack>
      </Alert>
    );
  return (
    <Alert
      color="red"
      variant="light"
      title={`${run.scenario} ${run.state === 'interrupted' ? 'was interrupted' : 'failed'}`}
    >
      <Text size="sm">{run.error || 'The background run stopped before its last step.'}</Text>
    </Alert>
  );
}
