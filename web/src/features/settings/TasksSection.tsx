import { Group, Stack, Text } from '@mantine/core';
import type { UseQueryResult } from '@tanstack/react-query';
import {
  useCan,
  useCosts,
  useHealth,
  useMe,
  useRecoveryControl,
  useSettings,
  useSiteProfile,
} from '@/api/hooks';
import { Section } from '@/components/Section';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { TRIAL } from '@/env/mode';
import { STATE_BADGES, summaryLine, taskReadiness, type Evidence, type TaskReadiness } from './tasks';

/** When the page last read a query, as an ISO UTC time; undefined before the first answer. */
const readAt = (q: Pick<UseQueryResult, 'dataUpdatedAt' | 'data'>) =>
  q.data !== undefined && q.dataUpdatedAt ? new Date(q.dataUpdatedAt).toISOString() : undefined;

const KIND_WORDS: Record<Evidence['kind'], string> = { 'set up': 'Set up', now: 'Now', seen: 'Seen' };

/**
 * One fact behind a task, by its kind, with when the run it names started, and the time the page read it where an old
 * reading could pass for current.
 */
function EvidenceLine({ e }: { e: Evidence }) {
  return (
    <Text size="xs" c="dimmed" data-kind={e.kind}>
      {KIND_WORDS[e.kind]}: {e.words}
      {e.started ? (
        <>
          {' '}
          Started <Timestamp iso={e.started} short size="xs" c="dimmed" focusable={false} />.
        </>
      ) : null}
      {e.at ? (
        <>
          {' '}
          Read <Timestamp iso={e.at} short size="xs" c="dimmed" focusable={false} />.
        </>
      ) : null}
    </Text>
  );
}

function TaskRow({ t }: { t: TaskReadiness }) {
  const badge = STATE_BADGES[t.state];
  // What stands in the way first; a limit is said after what the task does, since it can still be done
  const first = t.conditions.find((c) => c.effect !== 'limits') ?? t.conditions[0];
  const rest = t.conditions.filter((c) => c !== first);
  const limited = first?.effect === 'limits';
  return (
    <li
      data-testid={`task-${t.id}`}
      data-state={t.state}
      style={{ borderTop: '1px solid var(--mantine-color-default-border)', paddingTop: 8 }}
    >
      <Stack gap={4}>
        <Group justify="space-between" gap="xs" wrap="wrap" align="flex-start">
          <Text size="sm" fw={600} component="h3" m={0}>
            {t.title}
          </Text>
          <StatusBadge tone={badge.tone} label={badge.label} focusable={false} />
        </Group>
        {!first || limited ? <Text size="sm">{t.does}</Text> : null}
        {first ? (
          <Text size="sm" data-testid="task-condition" data-code={first.code}>
            {first.words}
          </Text>
        ) : null}
        {first?.next ? (
          <Text size="sm" data-testid="task-next">
            Next: {first.next}
          </Text>
        ) : null}
        {rest.map((c) => (
          <Text key={c.code} size="sm" c="dimmed" data-code={c.code}>
            Also: {c.words}
            {c.next ? ` ${c.next}` : ''}
          </Text>
        ))}
        {t.evidence.map((e) => (
          <EvidenceLine key={`${e.kind}:${e.words}`} e={e} />
        ))}
      </Stack>
    </li>
  );
}

/**
 * The tasks, read once the section is opened: who the reader is, the settings, the recovery control, the profile, the
 * health report's last live run and the costs.
 */
function TaskList() {
  const me = useMe();
  const can = useCan();
  const settings = useSettings();
  const recovery = useRecoveryControl();
  const profile = useSiteProfile();
  const health = useHealth();
  const costs = useCosts();
  if ([me, settings, recovery, profile, health, costs].some((q) => q.isPending))
    return (
      <Text size="sm" c="dimmed">
        Reading what you can do…
      </Text>
    );
  const tasks = taskReadiness({
    trial: TRIAL,
    signedIn: !!me.data,
    can,
    settings: settings.data,
    settingsAt: readAt(settings),
    recovery: recovery.data,
    recoveryAt: readAt(recovery),
    profile: profile.data?.profile,
    profileAt: readAt(profile),
    liveRuns: TRIAL ? undefined : costs.data?.totals?.liveRuns,
    // Undefined on an answer without the key, so the count stands in
    lastLive: TRIAL ? undefined : health.data?.last_live_run,
  });
  return (
    <Stack gap="sm">
      <Text size="sm" fw={600} data-testid="tasks-summary">
        {summaryLine(tasks)}.
      </Text>
      <Text size="sm" c="dimmed">
        {TRIAL
          ? 'What the trial lets you do, and what stands in the way.'
          : 'What you can do here now, and what to do when something stands in the way. Read only: each page checks again when you press.'}
      </Text>
      <Stack
        component="ul"
        gap="sm"
        m={0}
        p={0}
        style={{ listStyle: 'none' }}
        role="list"
        aria-label="Your tasks"
      >
        {tasks.map((t) => (
          <TaskRow key={t.id} t={t} />
        ))}
      </Stack>
    </Stack>
  );
}

/**
 * "Your tasks" (the external review's U145-04): for each task a person may come to do, whether it is ready for them
 * here now, what stands in the way and the next step, from what the app already reads. Read only: it changes nothing,
 * and each page checks again when its button is pressed. The first layer keeps one line, as Your access does; the list
 * opens from it, and only then reads what it rests on, so the page's own sections load as before. An explanation, not
 * data: it stays closed on Technical too.
 */
export function TasksSection() {
  return (
    <Section id="tasks" title="Your tasks">
      <TechDetail label="Each task, and whether it is ready" kind="explain" lazy>
        <TaskList />
      </TechDetail>
    </Section>
  );
}
