import { Anchor, Group, Text, ThemeIcon } from '@mantine/core';
import { IconCircleCheck } from '@tabler/icons-react';
import { Link } from 'react-router';
import { Term } from '@/components/Term';
import { PROOF, type Proof } from '@/lib/proof';
import { TONE_COLOURS } from '@/lib/tone';
import { useTechnical } from '@/stores/appearance';
import { proofParts } from './scenarioText';

/**
 * The proof under the hero, from the board's evaluation (lib/proof.ts), never typed: the board's proposals on the
 * scored passes, then the comparison played end to end, each on its own base, and the way to the evaluation. Technical
 * names the two bases. A sentence whose figures the evaluation cannot give is left out.
 */
export function ProofLine({ proof = PROOF }: { proof?: Pick<Proof, 'board' | 'played'> }) {
  const technical = useTechnical();
  const parts = proofParts(proof);
  if (!parts.tested && !parts.played) return null;
  const p = parts.played;
  return (
    <Group gap="sm" wrap="nowrap" align="flex-start" data-proof-line>
      <ThemeIcon variant="light" color={TONE_COLOURS.positive} radius="xl" size={26} aria-hidden>
        <IconCircleCheck size={18} />
      </ThemeIcon>
      <Text size="md" maw="68ch">
        {parts.tested}
        {parts.tested && p ? ' ' : null}
        {p ? (
          <>
            Played end to end on {p.of} {p.ofThem ? 'of them' : 'recorded failures'}: the board {p.board},{' '}
            <Term term="simple-rules">Rules only</Term> {p.rules}.
          </>
        ) : null}
        {technical && parts.bases ? ` ${parts.bases}` : null}{' '}
        <Anchor component={Link} to="/evaluation" fw={600}>
          See the evaluation
        </Anchor>
      </Text>
    </Group>
  );
}
