import { Card, Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';
import { hueVar, memberIdentity } from '@/lib/hues';
import { MemberAvatar } from './MemberAvatar';

/**
 * A board member's card: a 3 px top edge in the member's hue, its avatar beside its name, an optional role badge and
 * a small meta row (always visible: the run's facts an expert looks for), then the card's own content. Used by the
 * board on a case page, the board's answers in Ask and the Agent library.
 */
export function MemberCard({
  member,
  name,
  badge,
  meta,
  aside,
  titleOrder = 3,
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
  children?: ReactNode;
} & Omit<React.ComponentProps<'section'>, 'children'>) {
  const identity = memberIdentity(member);
  return (
    <Card
      component="section"
      padding="md"
      className="member-card"
      data-member={member}
      style={{ ['--mark-hue' as string]: hueVar(identity.hue) }}
      {...(rest as object)}
    >
      <Stack gap="sm">
        <Group justify="space-between" align="flex-start" wrap="nowrap" gap="sm">
          <Group gap="sm" wrap="nowrap" align="flex-start" style={{ minWidth: 0 }}>
            <MemberAvatar member={member} />
            <Stack gap={2} style={{ minWidth: 0 }}>
              <Group gap="xs" wrap="wrap">
                <Title order={titleOrder}>{name ?? identity.name}</Title>
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
