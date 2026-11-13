import { Box, Button, Card, Group, Stack, Text, ThemeIcon, Title } from '@mantine/core';
import { Link } from 'react-router';
import { useCases } from '@/api/hooks';
import type { CaseSummary, Mode } from '@/api/types';
import { MoreAbout } from './MoreAbout';

/**
 * The demo's guided path: the longer path through the recorded cases, for after the short route at the top of the page
 * (S2, S3 and S8 in Board mode), and then the Settings and Evaluation pages. It has no S2 step of its own, so the page
 * offers one start, the route's, and this path picks up where the route ends: the same S8 failure in Rules only. Each
 * step's case is found among the recorded cases by scenario and mode, never by a written-in id, so a recording made
 * again still links to the right case; a step whose recording is missing is left out. The demo build alone shows it.
 * Each step is a title, one sentence and its links; the rest of what it shows is behind "More".
 */
interface Step {
  title: string;
  /** One sentence of at most 20 words. */
  text: string;
  /** The rest, behind "More about step N". */
  more: string;
  /** The scenario whose case the step opens, and the mode it was played in (any mode when not given). */
  scenario?: string;
  mode?: Mode;
  /** The step also opens its case at the side-by-side of the scenario's rules and board cases. */
  compare?: boolean;
  /** The step opens the scenario's incident rather than its case. */
  incident?: boolean;
  /** Pages of the app, for a step that opens no case. */
  pages?: PageLink[];
}

interface PageLink {
  to: string;
  label: string;
}

const STEPS: Step[] = [
  {
    scenario: 'S8',
    mode: 'rules',
    title: 'S8 in Rules only: an unsafe resend allowed for demonstration',
    text: 'This demonstration deliberately lets Rules only resend despite two systems moving the patient at the same recorded time.',
    more: "Rules only is exempted here on purpose. Every check passes, and the approved resend writes WARD-B over the bed manager's WARD-C. In a real case, the gate blocks it.",
  },
  {
    scenario: 'S8',
    mode: 'board',
    title: "S8 in Board: two movements need a person's decision",
    text: 'The same failure on the board: the evidence cannot tell which movement is current, so a person decides.',
    more: 'The coordinator agent escalates, citing entry E7 (two sources at the same time). The side-by-side puts the two cases and the evidence they share next to each other.',
    compare: true,
  },
  {
    scenario: 'S15',
    title: 'S15: a merge withheld, escalated to the PAS team, marked handled',
    text: 'A patient merge (ADT^A40) is never sent by default: the gate blocks any plan that would send it.',
    more: 'The board is not convened, Escalate drafts the email to the PAS team, and Mark as handled by the team closes the case with what they did.',
  },
  {
    scenario: 'S11',
    incident: true,
    title: 'S11: the outage incident, with a chain per encounter',
    text: 'The receiver went down twice and eight deliveries failed: one incident, a chain per encounter.',
    more: 'Operations that still need resending are released in event order, one at a time. Each subsequent operation uses the receiver version verified after the previous one.',
  },
  {
    pages: [
      { to: '/settings', label: 'Settings and costs' },
      { to: '/evaluation', label: 'Evaluation' },
    ],
    title: 'Settings and costs, and the evaluation of the board',
    text: 'Every agent run with its model, tokens and cost, and how each board member scored.',
    more: "A replayed run costs nothing. The evaluation gives each board member's disposition and confidence per scenario, from the runs recorded with the real agents.",
  },
];

const newestFirst = (a: CaseSummary, b: CaseSummary) => b.openedAt.localeCompare(a.openedAt);

/** The scenario's latest case in the mode, or, when no mode is asked for, in board mode if there is one, else any. */
function caseFor(cases: CaseSummary[], scenario: string, mode?: Mode): CaseSummary | undefined {
  const ofScenario = cases.filter((c) => c.scenario === scenario).sort(newestFirst);
  if (mode) return ofScenario.find((c) => c.mode === mode);
  return ofScenario.find((c) => c.mode === 'board') ?? ofScenario[0];
}

/** Where a step leads: its pages, a case or an incident; nothing when its recording is missing. */
function linksFor(step: Step, cases: CaseSummary[]): PageLink[] {
  if (step.pages) return step.pages;
  if (!step.scenario) return [];
  if (step.incident) {
    const id = cases
      .filter((c) => c.scenario === step.scenario && c.incidentId)
      .sort(newestFirst)[0]?.incidentId;
    return id ? [{ to: `/incidents/${encodeURIComponent(id)}`, label: `Incident ${id}` }] : [];
  }
  const c = caseFor(cases, step.scenario, step.mode);
  if (!c) return [];
  const to = `/cases/${encodeURIComponent(c.caseId)}`;
  return [
    { to, label: `Case ${c.caseId}` },
    ...(step.compare ? [{ to: `${to}?show=compare`, label: 'Rules only and Board side by side' }] : []),
  ];
}

export function StartHere() {
  // The recorded cases, all of them: the demo's mock answers them from its recording whatever the limit.
  const cases = useCases({ limit: 100 });
  if (!cases.isSuccess) return null;
  const steps = STEPS.map((s) => ({ ...s, links: linksFor(s, cases.data.items) })).filter(
    (s) => s.links.length,
  );
  return (
    <Card padding="md" component="section" aria-labelledby="start-here-title">
      <Stack gap="sm">
        <Stack gap={2}>
          <Title order={2} id="start-here-title">
            Then follow this path
          </Title>
          <Text size="md" c="dimmed" maw="68ch">
            The longer path, for after the short route above. Approve, escalate and close replay here; nothing
            leaves your browser.
          </Text>
        </Stack>
        <Stack component="ol" gap="md" m={0} p={0} style={{ listStyle: 'none' }} className="start-here-steps">
          {steps.map((s, i) => (
            <Box component="li" key={s.title}>
              <Group gap="sm" wrap="nowrap" align="flex-start">
                <ThemeIcon size={26} radius="xl" variant="light" aria-hidden>
                  <Text span size="sm" fw={700}>
                    {i + 1}
                  </Text>
                </ThemeIcon>
                <Stack gap={4} style={{ minWidth: 0, flex: 1 }}>
                  <Group justify="space-between" align="flex-start" gap="xs" wrap="wrap">
                    <Text size="md" fw={600} style={{ flex: '1 1 260px' }}>
                      {s.title}
                    </Text>
                    <Group gap="xs" wrap="wrap">
                      {s.links.map((l) => (
                        <Button key={l.to} component={Link} to={l.to} size="compact-sm" variant="light">
                          {l.label}
                        </Button>
                      ))}
                    </Group>
                  </Group>
                  <Text size="md" maw="68ch">
                    {s.text}
                  </Text>
                  <MoreAbout about={`step ${i + 1}`}>
                    <Text size="sm" maw="68ch">
                      {s.more}
                    </Text>
                  </MoreAbout>
                </Stack>
              </Group>
            </Box>
          ))}
        </Stack>
      </Stack>
    </Card>
  );
}
