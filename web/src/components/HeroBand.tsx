import { Group, Paper, Stack, Text } from '@mantine/core';
import type { Icon } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { TONE_ICONS, toneText, type Tone } from '@/lib/tone';

/**
 * The first block of a detail or proof page: a 4 px top edge in a tone, the hero statement (24 px: the outcome or the
 * proof in plain words, at most 24 words), a status badge, and up to three facts as small tiles or a one-line meta row
 * (`children`). The moment of success for a verified delivery is a positive band with a check and the words
 * "Delivered: verified at the receiver"; no confetti, no celebration copy. `className` adds `outcome-band` on a case.
 */
export function HeroBand({
  tone,
  statement,
  status,
  overline,
  icon,
  label,
  children,
  className,
  tour,
  statementAs = 'p',
}: {
  tone: Tone;
  statement: ReactNode;
  status?: ReactNode;
  /** A small label above the statement ("THE BOARD AGAINST THE EXPECTED OUTCOME"). */
  overline?: ReactNode;
  /** The tone's icon unless another is given; none with `null`. */
  icon?: Icon | null;
  /** The band's region name. */
  label?: string;
  children?: ReactNode;
  className?: string;
  tour?: string;
  /** The statement as a paragraph, or as the page's second-level heading. */
  statementAs?: 'p' | 'h2';
}) {
  const I = icon === null ? null : (icon ?? TONE_ICONS[tone]);
  return (
    <Paper
      component="section"
      aria-label={label}
      p="lg"
      className={['hero-band', className].filter(Boolean).join(' ')}
      data-tone={tone}
      data-tour={tour}
    >
      <Stack gap="sm">
        {overline ? (
          <Text component="span" className="overline">
            {overline}
          </Text>
        ) : null}
        <Group gap="sm" align="flex-start" wrap="nowrap">
          {I ? (
            <I size={28} stroke={1.8} aria-hidden style={{ color: toneText(tone), flex: 'none' }} />
          ) : null}
          <Stack gap={6} style={{ minWidth: 0 }}>
            <Text component={statementAs} className="hero-statement" m={0}>
              {statement}
            </Text>
            {status ? <Group gap="xs">{status}</Group> : null}
          </Stack>
        </Group>
        {children}
      </Stack>
    </Paper>
  );
}
