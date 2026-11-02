import { Group, Text } from '@mantine/core';
import { hueVar, memberIdentity, SPECIALISTS } from '@/lib/hues';

/** The agreement levels' words, as the evaluation counts them. */
export const AGREEMENT_WORDS: Record<string, string> = {
  unanimous: 'Unanimous',
  'with the majority': 'With the majority',
  'with a minority': 'With a minority',
  'against all three': 'Against all three',
};

/**
 * How far the specialists agreed with the plan: one dot per specialist in member order (Conformance, Encounter
 * Integrity, Impact Analysis), filled in its hue when it proposed the plan's action and a hollow ring when it did not;
 * the coordinator writes the plan, so it has no dot. The dots are decoration: the agreement's words sit beside them.
 */
export function AgreementDots({
  proposed,
  agreement,
}: {
  /** Whether each specialist proposed the plan's action, by member code. */
  proposed: Partial<Record<(typeof SPECIALISTS)[number], boolean>>;
  /** The agreement level (unanimous, with the majority, with a minority, against all three), shown in words. */
  agreement?: string;
}) {
  return (
    <Group gap={6} wrap="nowrap" align="center">
      <span className="agreement-dots" aria-hidden>
        {SPECIALISTS.map((m) => (
          <span
            key={m}
            data-member={m}
            data-hollow={proposed[m] ? undefined : true}
            style={{ ['--mark-hue' as string]: hueVar(memberIdentity(m).hue) }}
          />
        ))}
      </span>
      {agreement ? (
        <Text size="sm" span>
          {AGREEMENT_WORDS[agreement] ?? agreement}
        </Text>
      ) : null}
    </Group>
  );
}
