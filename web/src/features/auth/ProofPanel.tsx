import { Anchor, Box, Group, SimpleGrid, Stack, Text, VisuallyHidden } from '@mantine/core';
import { useId } from 'react';
import { BrandMark } from '@/components/BrandMark';
import { CodeChip } from '@/components/CodeChip';
import { ComparisonBars } from '@/components/ComparisonBars';
import { StatTile } from '@/components/StatTile';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { trialHref } from '@/env/mode';
import { plural } from '@/lib/format';
import { PROOF, type Proof } from '@/lib/proof';
import { useDetail } from '@/stores/appearance';
import { APP_NAME, APP_TAGLINE } from '@/theme';

/** Where "Evaluation" opens: the trial's page, since the live one asks for a session and a signed-out page has none. */
const evaluationHref = () => trialHref('#/evaluation');

/** Underlined always: it stands in a line of text, and a link there must not rest on its colour alone. */
function EvaluationLink() {
  return (
    <Anchor href={evaluationHref()} underline="always">
      Evaluation
      <VisuallyHidden> in the trial</VisuallyHidden>
    </Anchor>
  );
}

/** What the figures measure, beside them: the agents did not reach these answers unaided. */
const GIVEN_THE_ENTRY = "The agents were given the catalogue's matching entry and preferred outcome.";

/**
 * The left half of the live sign-in page: what Shutter is for, in the app's best line, and the proof for it. The proof
 * (three tiles and where the runs were recorded) shows only where the figures describe the install in front of the
 * reader, a demo or the contest's own instance (`figures`); a hospital's own install shows the headline and the
 * purpose alone. Every figure comes from `lib/proof.ts` (the board's evaluation), never typed, and a figure the
 * document cannot give leaves its tile out. Each comparison keeps its own base (DESIGN.md, principle 7): the board's
 * 24 of 24 stands alone; the 11 against 4 are drawn as two bars on the same 11 failures, and 4 of 11 is never a figure
 * of its own. On a phone the tiles collapse into one line of text, so the sign-in form stays above the fold.
 */
export function ProofPanel({ figures, proof = PROOF }: { figures: boolean; proof?: Proof }) {
  const headline = useId();
  const technical = useDetail() === 'technical';
  const { board, played } = proof;
  const allMatched = board ? board.matched === board.scored : false;

  const phoneLine = [
    board && `Recorded failures: the board ${board.matched} of ${board.scored}.`,
    played &&
      `On the same ${plural(played.of, 'failure')}: the board ${played.board}, Rules only ${played.rules}.`,
    GIVEN_THE_ENTRY,
  ].filter((s): s is string => !!s);

  const recorded = proof.runs
    ? `From ${plural(proof.runs, 'run')} recorded with the real agents on IRIS AI Hub.`
    : 'Recorded with the real agents on IRIS AI Hub.';

  return (
    <Box
      component="section"
      aria-labelledby={headline}
      bg={{ base: 'transparent', md: 'var(--mantine-color-body)' }}
      bd={{ base: 'none', md: '1px solid var(--mantine-color-default-border)' }}
      bdrs="md"
      p={{ base: 0, md: 'xl' }}
    >
      <Stack gap="md">
        <Group gap="xs" hiddenFrom="md" data-viewport="phone">
          <BrandMark size={36} />
          <Text fw={700} fz="lg">
            {APP_NAME}
          </Text>
        </Group>
        <Text component="p" className="overline" m={0} visibleFrom="md" data-viewport="laptop">
          {APP_TAGLINE}
        </Text>
        <Text component="h2" id={headline} className="hero-statement" m={0} maw="26em">
          Shutter resends a failed <Term term="hl7">HL7 delivery</Term> only when its checks pass.
          Otherwise it stops and names the patient.
        </Text>
        <Text size="lg" m={0} maw="34em">
          When a patient movement fails to reach another system, Shutter finds out why.
        </Text>
        <TechDetail label="How it decides" kind="data">
          For HL7 v2 ADT feeds on InterSystems IRIS for Health: a fix is written only when the gate passes and
          a person, or the site&apos;s written policy, releases it.
        </TechDetail>

        {figures && (board || played) ? (
          <>
            <Text size="sm" hiddenFrom="md" data-viewport="phone" m={0}>
              {phoneLine.join(' ')} <EvaluationLink />
            </Text>
            <SimpleGrid cols={2} spacing="sm" visibleFrom="md" data-viewport="laptop">
              {board ? (
                <StatTile
                  label="Recorded failures"
                  figure={`${board.matched} of ${board.scored}`}
                  caption="where the board chose the expected action"
                  tone={allMatched ? 'positive' : 'attention'}
                  status={
                    <StatusBadge
                      tone={allMatched ? 'positive' : 'attention'}
                      label={allMatched ? 'As expected' : 'Not all as expected'}
                    />
                  }
                >
                  {technical ? (
                    <Text size="xs" c="dimmed">
                      scored passes, proposed action
                    </Text>
                  ) : null}
                </StatTile>
              ) : null}
              {played ? (
                <StatTile label="Head to head" figure={`${played.board} against ${played.rules}`}>
                  <ComparisonBars
                    of={played.of}
                    caption={`the board against Rules only (no agents), on the same ${plural(played.of, 'failure')}`}
                    bars={[
                      { label: 'The board', value: played.board, hue: 'violet' },
                      { label: 'Rules only', value: played.rules, hue: 'gray' },
                    ]}
                  />
                  {technical ? (
                    <Text size="xs" c="dimmed">
                      same scenarios, played end to end
                    </Text>
                  ) : null}
                </StatTile>
              ) : null}
              <Text size="sm" m={0} style={{ gridColumn: '1 / -1' }}>
                {GIVEN_THE_ENTRY}
              </Text>
              <Box style={{ gridColumn: '1 / -1' }}>
                <StatTile
                  label="Safety"
                  figure="Every write"
                  caption="gated, rehearsed, released and verified"
                />
              </Box>
            </SimpleGrid>
            <Box visibleFrom="md" data-viewport="laptop">
              <Text size="sm" c="dimmed" m={0}>
                {recorded} <EvaluationLink />
              </Text>
              {technical && proof.recordedOn ? (
                <Text size="xs" c="dimmed" mt={4}>
                  Image <CodeChip>{proof.recordedOn.image}</CodeChip>
                  {proof.models.length ? (
                    <>
                      , model{proof.models.length > 1 ? 's' : ''}{' '}
                      {proof.models.map((m, i) => (
                        <span key={m}>
                          {i ? ', ' : ''}
                          <CodeChip>{m}</CodeChip>
                        </span>
                      ))}
                    </>
                  ) : null}
                  .
                </Text>
              ) : null}
            </Box>
          </>
        ) : null}
      </Stack>
    </Box>
  );
}
