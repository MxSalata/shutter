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
import { TRIAL, trialHref } from '@/env/mode';
import { byEnv } from '@/env/copy';
import { TRIAL_BOARD_CASE } from '@/lib/hospital';
import type { Mode, Scenario } from '@/api/types';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { StateBadge } from '@/components/StateBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { caseOf } from '@/features/guide/places';
import { hueVar, MODE_IDENTITY } from '@/lib/hues';
import { MoreAbout } from './MoreAbout';
import { ScenarioDiagram } from './ScenarioDiagram';
import { ProofLine } from './ProofLine';

/** Where a role that sees no board can watch one decide: in the trial, S8's recording, wherever this page is. */
function BoardRecording() {
  return TRIAL ? (
    <Anchor component={Link} to={`/cases/${TRIAL_BOARD_CASE}`} inherit>
      S8&apos;s recording
    </Anchor>
  ) : (
    <Anchor href={trialHref(`#/cases/${TRIAL_BOARD_CASE}`)} inherit>
      S8&apos;s recording in the trial
    </Anchor>
  );
}

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
 * The page's opening: the proof in view, and behind "What a scenario does" the one sentence, what a scenario is, and the
 * six steps every case goes through. The steps' numbers are in the brand's light colour, since blue means running; the
 * gate's step carries its shield and the heavier words. Where the user may not run scenarios (`demo`, the online demo's
 * roles), the hospital's stories are settled by its written policy, so the words say that and name no board.
 */
export function ScenariosHero({ demo = false }: { demo?: boolean }) {
  return (
    <Stack
      gap="xs"
      component="section"
      aria-label="Shutter fixes a failed HL7 transfer only when its checks pass. Otherwise it stops and names the patient."
    >
      <ProofLine />
      <TechDetail label="What a scenario does" kind="explain">
        <Stack gap="sm">
          <Text component="h2" fz="lg" fw={600} m={0}>
            Shutter fixes a failed <Term term="hl7-transfer">HL7 transfer</Term> only when its checks pass.
            Otherwise it stops and names the patient.
          </Text>
          <Text size="md" maw="68ch">
            {demo ? (
              <>
                {byEnv({
                  live: "Here the site's written policy proposes the fix, with no agent:",
                  trial: "On the online demo the site's written policy proposes the fix, with no agent:",
                })}{' '}
                watch the gate check, a person or the policy release and the receiver verify. To see the board
                of IRIS AI Hub agents decide, open <BoardRecording />.
              </>
            ) : (
              'Watch a board of IRIS AI Hub agents investigate, the gate check, a person release and the receiver verify.'
            )}
          </Text>
          <Text size="sm" maw="68ch">
            Each scenario plays a known failure into the production: HL7 ADT files into its inbound folder and
            faults on the downstream system. Shutter opens a case, investigates, checks the plan at the gate,
            has a person or the site&apos;s written policy release it, and verifies the result at the
            receiver.
          </Text>
          <Box component="ol" className="step-strip" aria-label="What happens to every case">
            {STEPS.map((name, i) => {
              // The hospital's stories have no board where the user may not run scenarios
              const step = demo && name === 'Board plan' ? 'Plan' : name;
              const gate = step === 'Gate checks';
              return (
                <li key={step}>
                  <ThemeIcon size={24} radius="xl" variant="light" aria-hidden>
                    <Text span size="sm" fw={700}>
                      {i + 1}
                    </Text>
                  </ThemeIcon>
                  <Text span size="sm" fw={gate ? 700 : 400}>
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
        </Stack>
      </TechDetail>
    </Stack>
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
  /**
   * The card follows the mode chosen under Run mode, with its words for each mode it can be played in there: its Run
   * plays in that mode and says so ("Run S8 in Rules only"). Its own `mode` is the one it shows otherwise.
   */
  byMode?: Partial<Record<Mode, Pick<Featured, 'title' | 'see' | 'more' | 'diagramNote'>>>;
  /**
   * A line above the diagram, where the mode's run does not end as the diagram draws: the diagram is how the scenario
   * should end (scenarioDiagramModel.ts), so S8 in Rules only, which writes, says so in words.
   */
  diagramNote?: string;
}

/** Above S8's diagram in Rules only: the diagram draws the end S8 should have, and Rules only writes instead. */
export const S8_RULES_DIAGRAM_NOTE = 'Should end: a person decides. Rules only writes instead.';

/** S8 played by Rules only: the resend the scenario is exempted for, so that a plain resend can be seen writing. */
export const S8_RULES_SEE =
  'Rules only, exempted here on purpose to show a plain resend: every check passed and WARD-B was written over WARD-C. On a real case the gate holds it.';

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
      `A resend would write over the bed manager's ward with every check passed. The evidence cannot tell which movement is current, so the coordinator agent escalates to a person${entry ? `, citing catalogue entry ${entry},` : ''} and keeps the dissent.`,
    byMode: {
      rules: {
        title: 'Rules only writes over a ward',
        see: () => S8_RULES_SEE,
        diagramNote: S8_RULES_DIAGRAM_NOTE,
        more: 'Two systems moved the same patient at the same recorded time. With no agents, the plan is a plain resend; play S8 in Board mode next to see the coordinator agent escalate the same failure to a person.',
      },
      policy: {
        title: 'The policy leaves it to the board',
        see: (entry) =>
          `The site's written policy does not settle two movements at the same time, so the board takes the case: the evidence cannot tell which movement is current, and the coordinator agent escalates to a person${entry ? `, citing catalogue entry ${entry}` : ''}.`,
      },
      single: {
        title: 'One agent weighs a write',
        see: () =>
          "A resend would write over the bed manager's ward with every check passed. One generalist agent reads all the evidence and proposes the plan; the gate checks it as in every mode.",
      },
    },
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
 * the scenario's latest case in that mode, else its latest case in any mode under that case's own mode, and says so
 * where the link would be while the scenario has no case yet: the card's text is true before the hospital plays it.
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
      'A patient merge is never sent by default: the gate blocks every plan, in any mode, and the case goes to the PAS team, whose email Shutter drafts.',
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
  whyId,
  chosen,
}: {
  /** The scenarios, once read; the section and its heading render before that, as the guide's first target. */
  scenarios: Scenario[] | undefined;
  /** The mode chosen under Run mode, which a card with words for it follows (S8). */
  chosen?: Mode;
  failed: boolean;
  /** Why a scenario cannot be played in a mode now, or "" when it can. */
  why: (s: Scenario, mode: Mode) => string;
  starting: (s: Scenario, mode: Mode) => boolean;
  onRun: (s: Scenario, mode: Mode) => void;
  /**
   * True on the public demo, whose user may not run scenarios: the cards are the demo's three (DEMO_FIRST), each with
   * the case it has, and their Run buttons are greyed out, the reason said once in the element `whyId` names.
   */
  demo?: boolean;
  whyId?: string;
}) {
  const casesRead = useCases({ limit: 100 });
  const cases = casesRead.data?.items ?? [];
  // A card that follows the chosen mode takes that mode and its words for it (the demo's cards keep their own)
  const list = demo
    ? DEMO_FIRST
    : FIRST.map((f) => {
        const words = chosen && f.byMode ? f.byMode[chosen] : undefined;
        return words ? { ...f, ...words, mode: chosen!, follows: true } : { ...f, follows: !!f.byMode };
      });
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
      // The demo: the case in the mode, else the latest in any mode as the card's own; none, the card in its own mode
      const found = inMode ?? caseOf(cases, f.s.id);
      return found
        ? [{ ...f, mode: found.mode, inMode: found, latest: found }]
        : [{ ...f, inMode: undefined, latest: undefined }];
    });
  const ids = list.map((f) => f.id).join(', ');
  return (
    <section aria-labelledby="try-first-title" data-tour="scenarios">
      <Group gap="xs" align="baseline" mb="sm" wrap="wrap">
        <Title order={2} id="try-first-title">
          {demo ? 'Three to look at first' : 'Try these three first'}
        </Title>
        <Text size="md" c="dimmed">
          {demo
            ? byEnv({
                live: 'The hospital plays these in Site policy mode.',
                trial: "Recorded; the online demo's hospital plays these in Site policy mode.",
              })
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
          None of {ids} is among this install&apos;s scenarios.
        </Text>
      ) : (
        <SimpleGrid cols={{ base: 1, md: 3 }} spacing="md" verticalSpacing={{ base: 'md', md: 0 }}>
          {first.map(({ s, mode, title, see, more, diagramNote, inMode, latest, ...f }) => {
            const reason = why(s, mode);
            const modeName = MODE_NAMES[mode];
            // A card that follows the chosen mode names it on its Run: "Run S8 in Rules only"
            const follows = 'follows' in f && f.follows;
            return (
              <Card key={s.id} padding="md" data-first={s.id} className="first-card">
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
                    {diagramNote ? (
                      <Text size="xs" fw={600}>
                        {diagramNote}
                      </Text>
                    ) : null}
                    <ScenarioDiagram scenario={s} mode={mode} />
                  </Stack>
                  <Stack gap={4}>
                    <Text className="overline">{demo ? 'What it shows' : 'You will see'}</Text>
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
                  <Stack gap="xs" align="flex-start" className="first-actions">
                    <Tooltip label={reason || `Play ${s.id} in ${modeName} mode`} multiline maw={260}>
                      <span>
                        <Button
                          size="sm"
                          leftSection={<IconPlayerPlay size={16} />}
                          disabled={!!reason}
                          loading={starting(s, mode)}
                          onClick={() => onRun(s, mode)}
                          aria-label={`Run ${s.id} in ${modeName} mode`}
                          aria-describedby={demo ? whyId : undefined}
                          data-tour-action={`run-${s.id}`}
                        >
                          {follows ? `Run ${s.id} in ${modeName}` : `Run ${s.id}`}
                        </Button>
                      </span>
                    </Tooltip>
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
                    ) : demo ? (
                      // Until the cases are read it isn't known that there is none
                      casesRead.isSuccess ? (
                        <Text size="sm" c="dimmed">
                          {byEnv({
                            live: 'No case yet: the hospital plays one every few minutes.',
                            trial: "No recording of it here; the online demo's hospital plays it.",
                          })}
                        </Text>
                      ) : null
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
