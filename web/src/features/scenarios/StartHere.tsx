import { Anchor, Card, List, Stack, Text, Title } from '@mantine/core';
import { Link } from 'react-router';
import { useCases } from '@/api/hooks';
import type { CaseSummary, Mode } from '@/api/types';

/**
 * The demo's guided path: the recorded cases in the order the README's "Five minutes with Shutter" takes them. Each
 * step's case is found among the recorded cases by scenario and mode, never by a written-in id, so a recording made
 * again still links to the right case; a step whose recording is missing is left out. The demo build alone shows it.
 */
interface Step {
  title: string;
  text: string;
  /** The scenario whose case the step opens, and the mode it was played in (any mode when not given). */
  scenario?: string;
  mode?: Mode;
  /** The step opens the scenario's incident rather than its case. */
  incident?: boolean;
  /** A page of the app, for a step that opens no case. */
  to?: string;
  label?: string;
}

const STEPS: Step[] = [
  {
    scenario: 'S2',
    mode: 'board',
    title: 'S2 in board mode: approve, then verified',
    text: 'A transfer never arrived. Three specialists review the evidence, the coordinator proposes a resend, the gate passes it and the receiver\'s dry run says it would apply. Approve: one conditional write, then "Verified" from the receiver\'s own history.',
  },
  {
    scenario: 'S8',
    mode: 'rules',
    title: "S8 in Rules only mode: the resend that overwrote the bed manager's placement",
    text: "Two systems moved the same patient in the same minute. Rules alone pass every check, and the approved resend writes WARD-B over the bed manager's WARD-C.",
  },
  {
    scenario: 'S8',
    mode: 'board',
    title: 'S8 in board mode: escalated, citing catalogue entry E7',
    text: 'The same failure on the board: the evidence cannot decide which movement is current, so the coordinator escalates to a person, citing entry E7 (two sources at the same time).',
  },
  {
    scenario: 'S15',
    title: 'S15: a merge withheld, escalated to the PAS team, marked handled',
    text: 'A patient merge (ADT^A40) is never sent by default: the gate blocks every plan, the board is not convened, Escalate drafts the email to the PAS team, and Mark as handled by the team closes the case with what they did.',
  },
  {
    scenario: 'S11',
    incident: true,
    title: 'S11: the outage incident, with a chain per encounter',
    text: 'The receiver went down twice and eight deliveries failed: one incident, a chain per encounter in event order, released one operation at a time at the version the one before verified.',
  },
  {
    to: '/settings',
    label: 'Settings and costs',
    title: 'Settings and costs',
    text: 'Every agent run with its model, tokens, cache and cost; a replayed run costs nothing.',
  },
];

const newestFirst = (a: CaseSummary, b: CaseSummary) => b.openedAt.localeCompare(a.openedAt);

/** The scenario's latest case in the mode, or, when no mode is asked for, in board mode if there is one, else any. */
function caseFor(cases: CaseSummary[], scenario: string, mode?: Mode): CaseSummary | undefined {
  const ofScenario = cases.filter((c) => c.scenario === scenario).sort(newestFirst);
  if (mode) return ofScenario.find((c) => c.mode === mode);
  return ofScenario.find((c) => c.mode === 'board') ?? ofScenario[0];
}

/** Where a step leads: a case, an incident or a page; nothing when its recording is missing. */
function linkFor(step: Step, cases: CaseSummary[]): { to: string; label: string } | null {
  if (step.to) return { to: step.to, label: step.label ?? step.to };
  if (!step.scenario) return null;
  if (step.incident) {
    const id = cases
      .filter((c) => c.scenario === step.scenario && c.incidentId)
      .sort(newestFirst)[0]?.incidentId;
    return id ? { to: `/incidents/${encodeURIComponent(id)}`, label: `Incident ${id}` } : null;
  }
  const c = caseFor(cases, step.scenario, step.mode);
  return c ? { to: `/cases/${encodeURIComponent(c.caseId)}`, label: `Case ${c.caseId}` } : null;
}

export function StartHere() {
  // The recorded cases, all of them: the demo's mock answers them from its recording whatever the limit.
  const cases = useCases({ limit: 100 });
  if (!cases.isSuccess) return null;
  const steps = STEPS.map((s) => ({ ...s, link: linkFor(s, cases.data.items) })).filter((s) => s.link);
  return (
    <Card padding="md" component="section" aria-labelledby="start-here-title">
      <Stack gap="sm">
        <Stack gap={2}>
          <Title order={2} fz="lg" id="start-here-title">
            Start here
          </Title>
          <Text size="sm" c="dimmed">
            The recorded cases in the order the README takes them. The demo replays recorded runs in the
            browser, so Approve in step 1, and the escalation and the close in step 4, work here too; nothing
            leaves the browser.
          </Text>
        </Stack>
        <List type="ordered" spacing="sm">
          {steps.map((s) => (
            <List.Item key={s.title}>
              <Stack gap={2}>
                <Text size="sm" fw={600}>
                  {s.title}
                </Text>
                <Text size="sm">{s.text}</Text>
                <Anchor component={Link} to={s.link!.to} size="sm" fw={600} w="fit-content">
                  {s.link!.label}
                </Anchor>
              </Stack>
            </List.Item>
          ))}
        </List>
      </Stack>
    </Card>
  );
}
