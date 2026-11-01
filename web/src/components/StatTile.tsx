import { Box, Group, Paper, Stack, Text, ThemeIcon } from '@mantine/core';
import type { Icon } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import { Link } from 'react-router';
import { hueVar, type Hue } from '@/lib/hues';
import { TONE_COLOURS, TONE_ICONS, type Tone } from '@/lib/tone';

/**
 * One figure that is the proof or a filter: an overline label, the figure (28 px, or 40 px at `size="hero"`, in the
 * text colour, tabular), a caption of at most 8 words and, with a tone, a 4 px left edge, the tone's icon and a status
 * word (the tone never stands alone). A hue instead draws an identity icon and no edge. With `to` the whole tile is the
 * link; with `onClick` it is a button, and with `pressed` a toggle (`aria-pressed`) that filters, as the Cases list's
 * tiles do. Tiles earn their place: never one that repeats the next block's header, never a zero-count severity tile.
 */
export function StatTile({
  label,
  figure,
  caption,
  tone,
  status,
  hue,
  icon,
  to,
  onClick,
  pressed,
  size = 'default',
  children,
  'aria-label': ariaLabel,
  tour,
}: {
  label: ReactNode;
  figure: ReactNode;
  caption?: ReactNode;
  /** The tile's status tone: an edge, the tone's icon, and `status`'s words. */
  tone?: Tone;
  /** The status in words (a badge), required with a tone; a count's badge only when the count is above zero. */
  status?: ReactNode;
  /** An identity hue for the icon, when the tile is about a thing rather than a status. */
  hue?: Hue;
  icon?: Icon;
  to?: string;
  onClick?: () => void;
  /** A tile that filters: whether its filter is on. */
  pressed?: boolean;
  size?: 'default' | 'hero';
  /** A small key-value list or a bar under the caption. */
  children?: ReactNode;
  'aria-label'?: string;
  tour?: string;
}) {
  const I = icon ?? (tone ? TONE_ICONS[tone] : undefined);
  const mark = I ? (
    tone && !hue ? (
      <ThemeIcon
        variant="light"
        color={TONE_COLOURS[tone]}
        size={28}
        radius="md"
        className="tile-icon"
        aria-hidden
      >
        <I size={16} />
      </ThemeIcon>
    ) : (
      <span
        className="identity-mark tile-icon"
        style={{
          width: 28,
          height: 28,
          borderRadius: 8,
          ['--mark-hue' as string]: hue ? hueVar(hue) : undefined,
        }}
        aria-hidden
      >
        <I size={16} />
      </span>
    )
  ) : null;
  const body = (
    <Stack gap={4}>
      <Group justify="space-between" align="flex-start" wrap="nowrap" gap="xs">
        <Text component="span" className="overline">
          {label}
        </Text>
        {mark}
      </Group>
      <Text component="span" className="stat-figure" data-size={size === 'hero' ? 'hero' : undefined}>
        {figure}
      </Text>
      {caption ? (
        <Text component="span" size="sm" c="dimmed">
          {caption}
        </Text>
      ) : null}
      {status ? <Box>{status}</Box> : null}
      {children}
    </Stack>
  );
  const shared = {
    className: 'stat-tile',
    'data-tone': tone,
    'data-tour': tour,
    'aria-label': ariaLabel,
  };
  if (to)
    return (
      <Paper component={Link} to={to} p="md" data-interactive {...shared}>
        {body}
      </Paper>
    );
  if (onClick)
    return (
      <Paper
        component="button"
        type="button"
        onClick={onClick}
        aria-pressed={pressed}
        p="md"
        data-interactive
        w="100%"
        {...shared}
      >
        {body}
      </Paper>
    );
  return (
    <Paper p="md" {...shared}>
      {body}
    </Paper>
  );
}
