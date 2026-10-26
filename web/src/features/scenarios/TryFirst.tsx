import {
  Anchor,
  Box,
  Button,
  Card,
  Group,
  Paper,
  SimpleGrid,
  Stack,
  Text,
  ThemeIcon,
  Title,
  Tooltip,
} from '@mantine/core';
import { IconPlayerPlay, IconShieldCheck } from '@tabler/icons-react';
import { Link } from 'react-router';
import { useCases } from '@/api/hooks';
import type { Mode, Scenario } from '@/api/types';
import { StateBadge } from '@/components/StateBadge';
import { caseOf } from '@/features/guide/places';

/** The modes by the names the Scenarios page gives them. */
const MODE_NAMES: Record<Mode, string> = {
  board: 'Board',
  policy: 'Site policy',
  single: 'Single investigator',
  rules: 'Rules only',
};

/** What Shutter does with a failed delivery, in the order it does it; the gate is the step a write cannot pass without. */
const STEPS = ['Open case', 'Evidence', 'Board plan', 'Gate checks', 'Release', 'Verify'];

/** The page's opening: the one sentence, what a scenario is, and the six steps every case goes through. */
export function ScenariosHero() {
  return (
    <Card padding="lg" component="section" aria-labelledby="scenarios-headline">
      <Stack gap="sm">
        <Text id="scenarios-headline" component="h2" fz={{ base: 20, sm: 26 }} fw={700} lh={1.25} m={0}>
          When an HL7 transfer fails, Shutter works out what is true and fixes it only when it is safe.
        </Text>
        <Text size="sm" c="dimmed" maw="90ch">
          Each scenario plays a known failure into the production: HL7 ADT files into its inbound folder and
          faults on the downstream system. Shutter opens a case, investigates, checks the plan at the gate,
          has a person or the site&apos;s written policy release it, and verifies the result at the receiver.
        </Text>
        <Box component="ol" className="step-strip" aria-label="What happens to every case">
          {STEPS.map((step, i) => {
            const gate = step === 'Gate checks';
            return (
              <li key={step} data-gate={gate || undefined}>
                <ThemeIcon size={22} radius="xl" variant="light" color="blue" aria-hidden>
                  <Text span size="xs" fw={700}>
                    {i + 1}
                  </Text>
                </ThemeIcon>
                <Text span size="sm" fw={600}>
                  {step}
                </Text>
                {gate ? <IconShieldCheck size={16} aria-hidden /> : null}
              </li>
            );
          })}
        </Box>
        <Text size="xs" c="dimmed">
          Nothing is written unless the gate passes the plan, and an unknown blocks a write as surely as a
          failure.
        </Text>
      </Stack>
    </Card>
  );
}

/**
 * The three scenarios to try first, each in the mode that shows what it is for: a recovery, a write the board
 * withholds, and a write the gate stops. Each links to its latest case in that mode, found among the cases by scenario
 * and mode (never a written-in id), else to the scenario's latest case in any mode.
 */
const FIRST: { id: string; mode: Mode; title: string; see: string }[] = [
  {
    id: 'S2',
    mode: 'board',
    title: 'A failed transfer recovered',
    see: "One conditional resend that waits for approval. Approve it, and the receiver's own history verifies the effect.",
  },
  {
    id: 'S8',
    mode: 'board',
    title: 'The board withholds a write',
    see: 'Three specialists and the coordinator. The evidence cannot decide which movement is current, so the coordinator escalates to a person, citing catalogue entry E7, and keeps the dissent.',
  },
  {
    id: 'S20',
    mode: 'rules',
    title: 'The gate stops a write',
    see: "The approval was bound to the receiver's version, and the nurse's move changed it, so the approval no longer holds: the gate blocks the resend and nothing is written.",
  },
];

export function TryFirst({
  scenarios,
  why,
  starting,
  onRun,
}: {
  scenarios: Scenario[];
  /** Why a scenario cannot be played in a mode now, or "" when it can. */
  why: (s: Scenario, mode: Mode) => string;
  starting: (s: Scenario, mode: Mode) => boolean;
  onRun: (s: Scenario, mode: Mode) => void;
}) {
  const cases = useCases({ limit: 100 }).data?.items ?? [];
  const first = FIRST.map((f) => ({ ...f, s: scenarios.find((s) => s.id === f.id) })).filter(
    (f): f is (typeof FIRST)[number] & { s: Scenario } => !!f.s,
  );
  if (!first.length) return null;
  return (
    <section aria-labelledby="try-first-title" data-tour="scenarios">
      <Group gap="xs" align="baseline" mb="xs" wrap="wrap">
        <Title order={2} fz="lg" id="try-first-title">
          Try these three first
        </Title>
        <Text size="sm" c="dimmed">
          Each one in the mode that shows what it is for.
        </Text>
      </Group>
      <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md">
        {first.map(({ s, mode, title, see }) => {
          const inMode = caseOf(cases, s.id, mode);
          const latest = inMode ?? (s.latestCase ? { ...s.latestCase, mode: undefined } : undefined);
          const reason = why(s, mode);
          const modeName = MODE_NAMES[mode];
          return (
            <Card key={s.id} padding="md">
              <Stack gap="sm" h="100%">
                <Stack gap={2}>
                  <Text size="xs" c="dimmed" fw={600}>
                    {s.id}, {modeName} mode
                  </Text>
                  <Title order={3} fz="md">
                    {title}
                  </Title>
                  <Text size="sm">{s.title}</Text>
                </Stack>
                <Paper p="sm" bg="var(--mantine-color-default-hover)" radius="sm">
                  <Text size="xs" fw={700} c="dimmed" tt="uppercase">
                    You will see
                  </Text>
                  <Text size="sm">{see}</Text>
                </Paper>
                <div style={{ flex: 1 }} />
                <Group justify="space-between" gap="xs" wrap="wrap">
                  <Tooltip label={reason || `Play ${s.id} in ${modeName} mode`} multiline maw={260}>
                    <span>
                      <Button
                        size="xs"
                        leftSection={<IconPlayerPlay size={14} />}
                        disabled={!!reason}
                        loading={starting(s, mode)}
                        onClick={() => onRun(s, mode)}
                        aria-label={`Run ${s.id} in ${modeName} mode`}
                      >
                        Run {s.id}
                      </Button>
                    </span>
                  </Tooltip>
                  {latest ? (
                    <Group gap={6} wrap="nowrap">
                      <Anchor
                        component={Link}
                        to={`/cases/${encodeURIComponent(latest.caseId)}`}
                        size="sm"
                        fw={600}
                        aria-label={`Open ${latest.caseId}, the latest ${s.id} case${inMode ? ` in ${modeName} mode` : ''}`}
                      >
                        Open {latest.caseId}
                      </Anchor>
                      <StateBadge state={latest.state} size="xs" />
                    </Group>
                  ) : (
                    <Text size="xs" c="dimmed">
                      Not played since the last reset
                    </Text>
                  )}
                </Group>
                {latest && !inMode ? (
                  <Text size="xs" c="dimmed">
                    Its latest case, in any mode: none in {modeName} mode among the newest cases.
                  </Text>
                ) : null}
              </Stack>
            </Card>
          );
        })}
      </SimpleGrid>
    </section>
  );
}
