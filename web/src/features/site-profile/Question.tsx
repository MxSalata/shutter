import { Group, Stack, Text, Tooltip, VisuallyHidden } from '@mantine/core';
import { IconArchive, IconSettingsBolt } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { CodeChip } from '@/components/CodeChip';
import { TechDetail } from '@/components/TechDetail';
import { HINT_EVENTS } from '@/theme';
import { EFFECT_WORDS } from './profile';

/**
 * Whether Shutter acts on an answer, or keeps it on record for the board and reviewers: an icon whose tooltip and name
 * are the words. In the legend, where the words sit beside it, it is decorative.
 */
export function Effect({ acts, decorative = false }: { acts: boolean; decorative?: boolean }) {
  const words = acts ? EFFECT_WORDS.acts : EFFECT_WORDS.record;
  const I = acts ? IconSettingsBolt : IconArchive;
  const mark = (
    <span
      {...(decorative ? { 'aria-hidden': true } : { role: 'img', 'aria-label': words, tabIndex: 0 })}
      className={decorative ? 'identity-mark' : 'identity-mark mantine-focus-auto'}
      data-effect={acts ? 'acts' : 'record'}
      style={{
        width: 24,
        height: 24,
        borderRadius: '50%',
        flex: 'none',
        ['--mark-hue' as string]: acts ? 'var(--mantine-color-text)' : 'var(--mantine-color-dimmed)',
      }}
    >
      <I size={14} stroke={1.8} aria-hidden />
    </span>
  );
  return decorative ? (
    mark
  ) : (
    <Tooltip label={words} events={HINT_EVENTS}>
      {mark}
    </Tooltip>
  );
}

/**
 * One question of the induction: its number in a circle, the question in 600 weight, and the icon that says whether the
 * answer changes what Shutter does. The number is also said to a screen reader ("Question 7:").
 */
export function Question({ n, text, acts }: { n: number; text: ReactNode; acts: boolean }) {
  return (
    <Group gap="sm" wrap="nowrap" align="flex-start" data-question={n}>
      <span
        aria-hidden
        className="identity-mark"
        style={{
          width: 24,
          height: 24,
          borderRadius: '50%',
          fontSize: 13,
          fontWeight: 600,
          fontVariantNumeric: 'tabular-nums',
        }}
      >
        {n}
      </span>
      <Text fw={600} size="md" style={{ flex: 1, minWidth: 0 }}>
        <VisuallyHidden component="span">{`Question ${n}: `}</VisuallyHidden>
        {text}
      </Text>
      <Effect acts={acts} />
    </Group>
  );
}

/** A key of the profile, what is stored under it, and what the core reads when nothing is stored. */
export type KeyRow = [path: string, stored: unknown, whenNotSet?: string];

/** A stored value as an engineer would write it: text as it is, a list joined, nothing as "not stored". */
function stored(value: unknown): string {
  if (value === undefined || value === null) return 'not stored';
  if (Array.isArray(value)) return value.length ? value.join(', ') : '[]';
  if (typeof value === 'object') return JSON.stringify(value);
  return value === '' ? '""' : String(value);
}

/**
 * A question's second layer. "Keys and values" (data: opens in Technical) starts with the profile key path as a code
 * chip, the name the API's own errors use, then what is stored under it and what is read when nothing is. "More about
 * this question" (explain: closed in both modes) holds the prose past the description's 25 words. A fold that belongs
 * to the question (`first`: an advanced field) heads the list, so the question's disclosures read as one.
 */
export function QuestionDetails({
  keys,
  more,
  first,
}: {
  keys: KeyRow[];
  more?: ReactNode;
  first?: ReactNode;
}) {
  return (
    <Stack gap={0}>
      {first}
      <TechDetail label="Keys and values" kind="data">
        <Stack gap={4}>
          {keys.map(([path, value, whenNotSet]) => (
            <Group key={path} gap={6} wrap="wrap" align="baseline">
              <CodeChip>{path}</CodeChip>
              <Text span size="sm">
                stored as
              </Text>
              <CodeChip>{stored(value)}</CodeChip>
              {whenNotSet ? (
                <Text span size="sm" c="dimmed">
                  When not set: {whenNotSet}.
                </Text>
              ) : null}
            </Group>
          ))}
        </Stack>
      </TechDetail>
      {more ? (
        <TechDetail label="More about this question" kind="explain">
          <Text size="sm" maw="68ch">
            {more}
          </Text>
        </TechDetail>
      ) : null}
    </Stack>
  );
}
