import { Card, Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';
import { hueVar, memberIdentity } from '@/lib/hues';
import { MemberAvatar } from './MemberAvatar';

/**
 * A board member's card: a 3 px top edge in the member's hue, its avatar beside its name, an optional role badge and
 * a small meta row (always visible: the run's facts an expert looks for), then the card's own content. Used by the
 * board on a case page, the board's answers in Ask and the Agent library.
 *
 * A `section` by default, or `component="article"` for a card that stands alone in a list of members (the library).
 * `titleId` is the heading's id: the card is then named by its heading, unless the caller names it, and a toggle
 * inside can be described by it. `muted` draws a member that is not enabled or did not take part: its edge and avatar
 * in gray, its own icon kept, and no fade (a fade would lower the text's contrast). A caller's `className` and `style`
 * are added to the card's own, so the hue and the class that draws the edge stay.
 */
export function MemberCard({
  member,
  name,
  badge,
  meta,
  aside,
  titleOrder = 3,
  titleId,
  component = 'section',
  muted = false,
  className,
  style,
  children,
  ...rest
}: {
  /** The member's code, for its hue and icon. */
  member: string;
  /** The name to show; the member's own name when absent. */
  name?: ReactNode;
  /** A badge after the name (the role as an IdentityBadge, the member's proposal). */
  badge?: ReactNode;
  /** A small row under the name. */
  meta?: ReactNode;
  /** Controls at the card's right (the library's switches). */
  aside?: ReactNode;
  titleOrder?: 2 | 3 | 4;
  /** The heading's id, for `aria-labelledby` on the card or a toggle inside it. */
  titleId?: string;
  /** The card's element: a section, or an article for a card that stands alone in a list. */
  component?: 'section' | 'article';
  /** A member that is not enabled or did not take part: gray edge and avatar. */
  muted?: boolean;
  children?: ReactNode;
} & Omit<React.ComponentProps<'section'>, 'children'>) {
  const identity = memberIdentity(member);
  // Named by its heading when the caller gives the heading's id and no name of its own
  const labelled = !!titleId && !rest['aria-label'] && !rest['aria-labelledby'];
  return (
    <Card
      component={component}
      padding="md"
      data-member={member}
      data-muted={muted || undefined}
      aria-labelledby={labelled ? titleId : undefined}
      {...(rest as object)}
      className={['member-card', className].filter(Boolean).join(' ')}
      style={{ ['--mark-hue' as string]: hueVar(muted ? 'gray' : identity.hue), ...style }}
    >
      <Stack gap="sm">
        <Group justify="space-between" align="flex-start" wrap="nowrap" gap="sm">
          <Group gap="sm" wrap="nowrap" align="flex-start" style={{ minWidth: 0 }}>
            <MemberAvatar member={member} muted={muted} />
            <Stack gap={2} style={{ minWidth: 0 }}>
              <Group gap="xs" wrap="wrap">
                <Title order={titleOrder} id={titleId}>
                  {name ?? identity.name}
                </Title>
                {badge}
              </Group>
              {meta ? (
                <Text size="xs" c="dimmed" component="div">
                  {meta}
                </Text>
              ) : null}
            </Stack>
          </Group>
          {aside}
        </Group>
        {children}
      </Stack>
    </Card>
  );
}
