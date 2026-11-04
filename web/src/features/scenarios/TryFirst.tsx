import {
  Anchor,
  Box,
  Button,
  Card,
  Group,
  Loader,
  SimpleGrid,
  Stack,
  Text,
  ThemeIcon,
  Title,
  Tooltip,
} from '@mantine/core';
import { IconPlayerPlay, IconShieldCheck } from '@tabler/icons-react';
import { Link } from 'react-router';
import { useCases, usePlan } from '@/api/hooks';
import type { Mode, Scenario } from '@/api/types';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { StateBadge } from '@/components/StateBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { caseOf } from '@/features/guide/places';
import { hueVar, MODE_IDENTITY } from '@/lib/hues';
import { MoreAbout } from './MoreAbout';
import { ProofLine } from './ProofLine';

/** The modes by the names the Scenarios page gives them. */
const MODE_NAMES: Record<Mode, string> = {
  board: 'Board',
  policy: 'Site policy',
  single: 'Single investigator',
  rules: 'Rules only',
};

/** A run mode's name with its identity dot (Board violet, Site policy teal, the others gray); the words say it. */
export function ModeName({ mode, children }: { mode: Mode; children?: React.ReactNode }) {
  const identity = MODE_IDENTITY[mode];
  return (
    <Group gap={6} wrap="nowrap" component="span" display="inline-flex">
      <span
        className="identity-dot"
        style={{ ['--mark-hue' as string]: hueVar(identity?.hue ?? 'gray') }}
        aria-hidden
      />
      {children ?? MODE_NAMES[mode]}
    </Group>
  );
}

/** What Shutter does with a failed delivery, in the order it does it; the gate is the step a write cannot pass without. */
const STEPS = ['Open case', 'Evidence', 'Board plan', 'Gate checks', 'Release', 'Verify'];

/**
 * The page's opening: the one sentence, what a scenario is, the six steps every case goes through, and the proof. The
 * steps' numbers are in the brand's light colour, since blue means running; the gate's step carries its shield. Where
 * the user may not run scenarios (`demo`, the online demo's roles), the hospital's stories are settled by its written
 * policy, so the words say that and name no board.
 */
export function ScenariosHero({ demo = false }: { demo?: boolean }) {
  return (
    <Card padding="lg" component="section" aria-labelledby="scenarios-headline">
      <Stack gap="sm">
        <Text id="scenarios-headline" component="h2" fz={{ base: 22, sm: 26 }} fw={600} lh={1.25} m={0}>
          When an <Term term="hl7-transfer">HL7 transfer</Term> fails, Shutter works out what is true and
          fixes it only when it is safe.
        </Text>
        <Text size="md" maw="68ch">
          {demo
            ? "Each scenario plays a known failure. Here the site's written policy proposes the fix, with no agent: watch the gate check, a person or the policy release and the receiver verify."
            : 'Each scenario plays a known failure. Watch a board of IRIS AI Hub agents investigate, the gate check, a person release and the receiver verify.'}
        </Text>
        <TechDetail label="What a scenario does" kind="explain">
          <Text size="sm" maw="68ch">
            Each scenario plays a known failure into the production: HL7 ADT files into its inbound folder and
            faults on the downstream system. Shutter opens a case, investigates, checks the plan at the gate,
            has a person or the site&apos;s written policy release it, and verifies the result at the
            receiver.
          </Text>
        </TechDetail>
        <Box component="ol" className="step-strip" aria-label="What happens to every case">
          {STEPS.map((step, i) => {
            const gate = step === 'Gate checks';
            return (
              <li key={step} data-gate={gate || undefined}>
                <ThemeIcon size={24} radius="xl" variant="light" aria-hidden>
                  <Text span size="sm" fw={700}>
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
        <Text size="sm" c="dimmed">
          Nothing is written unless the gate passes the plan; an unknown blocks a write too.
        </Text>
        <ProofLine />
      </Stack>
    </Card>
  );
}

/**
 * The three scenarios to try first, each in the mode that shows what it is for: a recovery, a write the board
 * withholds, and a write the gate stops. Each links to its latest case in that mode, found among the cases by scenario
 * and mode (never a written-in id), else to the scenario's latest case in any mode.
 *
 * What you will see follows each scenario's definition (its expected disposition, write, blocking check and final
 * reason; ScenariosPage.test checks each claim against fixtures/scenarios.json). The catalogue entry S8's coordinator
 * cites is read from the plan of its latest board case, and left unsaid until there is one.
 */
interface Featured {
  id: string;
  mode: Mode;
  title: string;
  see: (entry?: string) => string;
  /** The rest, behind "More about <id>", where the short text leaves something out. */
  more?: string;
}

const FIRST: Featured[] = [
  {
    id: 'S2',
    mode: 'board',
    title: 'A failed transfer recovered',
    see: () =>
      "One conditional resend that waits for approval. Approve it, and the receiver's own history verifies the effect.",
  },
  {
    id: 'S8',
    mode: 'board',
    title: 'The board withholds a write',
    see: (entry) =>
      `The evidence cannot tell which movement is current, so the coordinator agent escalates to a person${entry ? `, citing catalogue entry ${entry},` : ''} and keeps the dissent.`,
  },
  {
    id: 'S20',
    mode: 'rules',
    title: 'The gate stops a write',
    see: () =>
      "The approval stops holding when a nurse's move changes the record; the gate blocks the replanned resend, and nothing is written.",
    more: "The resend waits for approval, bound to the receiver's version. A nurse's move by hand changes that version, so the approval no longer holds; planned again, the resend is superseded by the later move, the gate blocks it and nothing is written.",
  },
];

/**
 * The public demo's three: its hospital plays its rotation by itself, in Site policy mode (S8 is out of it and S20 never
 * in it), so the cards are three of the rotation's stories, in the mode they are played in: a recovery the written
 * policy holds for a person, a case that waits on another patient's case, and a write the gate withholds. A card shows
 * the scenario's latest case in that mode, else its latest case in any mode under that case's own mode, and is left out
 * while the scenario has no case at all: there is no Run to offer instead.
 */
const DEMO_FIRST: Featured[] = [
  {
    id: 'S2',
    mode: 'policy',
    title: 'A failed transfer recovered',
    see: (entry) =>
      `A transfer that never arrived${entry ? ` (catalogue entry ${entry})` : ''}: the site's written policy holds the one conditional resend for a person. Approve it, and the receiver's own history verifies the effect.`,
  },
  {
    id: 'S23a',
    mode: 'policy',
    title: 'One case waits for another',
    see: () =>
      "The receiver refuses the transfer: the bed is held by a patient whose own transfer out failed a moment before. Shutter reads who holds the bed, as a token, and once that patient's case frees it, this one is resent into the bed.",
    more: "The receiver answers 409 bed_occupied. Shutter reads the occupant as a token, never the other patient's identifiers, and finds them leaving in another case; this case waits for that one, and when its resend lands, this transfer is released and resent into the freed bed, then verified from the receiver's history.",
  },
  {
    id: 'S15',
    mode: 'policy',
    title: 'The gate withholds a write',
    see: () =>
      'A patient merge is never sent by default: the gate blocks every plan, no board is convened, and the case goes to the PAS team, whose email Shutter drafts.',
    more: "The PAS merges an older record into the admitted patient (ADT^A40). A merge changes which record a patient's history belongs to, so the gate withholds it (MERGE_WITHHELD) and Escalate drafts the email to the team the site profile names for merges from the PAS; nothing is written.",
  },
];

/** What you will see, with the catalogue entry the case's plan cites when the card has a case in its mode. */
function SeeWithEntry({ caseId, see }: { caseId: string; see: (entry?: string) => string }) {
  const plan = usePlan(caseId, false).data;
  return <Text size="md">{see(plan?.plan?.catalogueEntry || undefined)}</Text>;
}

export function TryFirst({
  scenarios,
  failed,
  why,
  starting,
  onRun,
  demo = false,
}: {
  /** The scenarios, once read; the section and its heading render before that, as the guide's first target. */
  scenarios: Scenario[] | undefined;
  failed: boolean;
  /** Why a scenario cannot be played in a mode now, or "" when it can. */
  why: (s: Scenario, mode: Mode) => string;
  starting: (s: Scenario, mode: Mode) => boolean;
  onRun: (s: Scenario, mode: Mode) => void;
  /**
   * True on the public demo, whose user may not run scenarios: the cards are the demo's three (DEMO_FIRST), each with
   * the case it has, and no Run buttons.
   */
  demo?: boolean;
}) {
  const cases = useCases({ limit: 100 }).data?.items ?? [];
  const list = demo ? DEMO_FIRST : FIRST;
  const first = list
    .map((f) => ({ ...f, s: scenarios?.find((s) => s.id === f.id) }))
    .filter((f): f is Featured & { s: Scenario } => !!f.s)
    .flatMap((f) => {
      const inMode = caseOf(cases, f.s.id, f.mode);
      if (!demo)
        return [
          {
            ...f,
            inMode,
            latest: inMode ?? (f.s.latestCase ? { ...f.s.latestCase, mode: undefined } : undefined),
          },
        ];
      // The demo: the case in the mode, else the latest in any mode as the card's own; none, no card
      const found = inMode ?? caseOf(cases, f.s.id);
      return found ? [{ ...f, mode: found.mode, inMode: found, latest: found }] : [];
    });
  const ids = list.map((f) => f.id).join(', ');
  return (
    <section aria-labelledby="try-first-title" data-tour="scenarios">
      <Group gap="xs" align="baseline" mb="sm" wrap="wrap">
        <Title order={2} id="try-first-title">
          Try these three first
        </Title>
        <Text size="md" c="dimmed">
          {demo
            ? "The demo's hospital plays these by itself, in Site policy mode."
            : 'Each one in the mode that shows what it is for.'}
        </Text>
      </Group>
      {!scenarios ? (
        failed ? (
          <Text size="sm" c="dimmed">
            The scenarios could not be read, so these three cannot be offered yet.
          </Text>
        ) : (
          <Group gap="xs">
            <Loader size="xs" />
            <Text size="sm" c="dimmed">
              Loading the scenarios…
            </Text>
          </Group>
        )
      ) : !first.length ? (
        <Text size="sm" c="dimmed">
          {demo
            ? `None of ${ids} has a case among the newest yet: the demo's hospital plays one every few minutes.`
            : `None of ${ids} is among this install's scenarios.`}
        </Text>
      ) : (
        <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md">
          {first.map(({ s, mode, title, see, more, inMode, latest }) => {
            const reason = why(s, mode);
            const modeName = MODE_NAMES[mode];
            return (
              <Card key={s.id} padding="md" data-first={s.id}>
                <Stack gap="sm" style={{ flex: 1 }}>
                  <Stack gap={4}>
                    <Text component="div" className="overline">
                      <Group gap={6} wrap="nowrap" component="span" display="inline-flex">
                        <span>{s.id} ·</span>
                        <ModeName mode={mode} />
                      </Group>
                    </Text>
                    <Title order={3} fw={600}>
                      {title}
                    </Title>
                    <Text size="sm">{s.title}</Text>
                  </Stack>
                  <Stack gap={4}>
                    <Text className="overline">You will see</Text>
                    {inMode ? (
                      <SeeWithEntry caseId={inMode.caseId} see={see} />
                    ) : (
                      <Text size="md">{see()}</Text>
                    )}
                    {more ? (
                      <MoreAbout about={s.id}>
                        <Text size="sm">{more}</Text>
                      </MoreAbout>
                    ) : null}
                  </Stack>
                  {/* The action row sits at the card's foot, so the three Run buttons line up */}
                  <Stack gap="xs" mt="auto" align="flex-start">
                    {demo ? null : (
                      <Tooltip label={reason || `Play ${s.id} in ${modeName} mode`} multiline maw={260}>
                        <span>
                          <Button
                            size="sm"
                            leftSection={<IconPlayerPlay size={16} />}
                            disabled={!!reason}
                            loading={starting(s, mode)}
                            onClick={() => onRun(s, mode)}
                            aria-label={`Run ${s.id} in ${modeName} mode`}
                            data-tour-action={`run-${s.id}`}
                          >
                            Run {s.id}
                          </Button>
                        </span>
                      </Tooltip>
                    )}
                    {!demo && reason ? (
                      <Text size="xs" c="dimmed">
                        {reason}
                      </Text>
                    ) : null}
                    {latest ? (
                      <Group gap={8} wrap="wrap">
                        <Anchor
                          component={Link}
                          to={`/cases/${encodeURIComponent(latest.caseId)}`}
                          size="sm"
                          fw={600}
                          aria-label={`Open ${latest.caseId}, the latest ${s.id} case${inMode ? ` in ${modeName} mode` : ''}`}
                        >
                          Open {latest.caseId}
                        </Anchor>
                        {inMode ? (
                          <OutcomeBadge c={inMode} scenario={s} />
                        ) : (
                          <StateBadge state={latest.state} />
                        )}
                      </Group>
                    ) : (
                      <Text size="sm" c="dimmed">
                        Not played since the last reset
                      </Text>
                    )}
                    {latest && !inMode ? (
                      <Text size="sm" c="dimmed">
                        Its latest case, in any mode: none in {modeName} mode among the newest cases.
                      </Text>
                    ) : null}
                  </Stack>
                </Stack>
              </Card>
            );
          })}
        </SimpleGrid>
      )}
    </section>
  );
}
