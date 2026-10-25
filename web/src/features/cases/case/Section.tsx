import { Card, Group, Stack, Text, Title } from '@mantine/core';
import { createContext, useContext, type ReactNode } from 'react';

/**
 * Whether a section sits inside one of the case summary's story steps: there it is a plain region with a smaller
 * heading, since the step's own heading and card already frame it.
 */
const Nested = createContext(false);

export function NestedSections({ children }: { children: ReactNode }) {
  return <Nested.Provider value>{children}</Nested.Provider>;
}

/** One step of the case's story: a card with a heading, an optional note under it and a badge on the right. */
export function Section({
  id,
  title,
  note,
  aside,
  children,
}: {
  id: string;
  title: ReactNode;
  note?: ReactNode;
  aside?: ReactNode;
  children: ReactNode;
}) {
  const nested = useContext(Nested);
  const body = (
    <Stack gap="sm">
      <Group justify="space-between" align="flex-start" wrap="wrap" gap="xs">
        <Stack gap={2} style={{ minWidth: 0, flex: '1 1 260px' }}>
          {/* Focusable from script only: a link to a section (Review the plan and decide) moves focus to its heading */}
          <Title order={nested ? 3 : 2} fz={nested ? 'md' : 'lg'} id={`${id}-title`} tabIndex={-1}>
            {title}
          </Title>
          {note ? (
            <Text size="sm" c="dimmed">
              {note}
            </Text>
          ) : null}
        </Stack>
        {aside ? <Group gap={6}>{aside}</Group> : null}
      </Group>
      {children}
    </Stack>
  );
  if (nested)
    return (
      <section id={id} aria-labelledby={`${id}-title`}>
        {body}
      </section>
    );
  return (
    <Card padding="md" id={id} component="section" aria-labelledby={`${id}-title`}>
      {body}
    </Card>
  );
}

/** What a section shows before its step has happened. */
export function NotYet({ children }: { children: ReactNode }) {
  return (
    <Text size="sm" c="dimmed" fs="italic">
      {children}
    </Text>
  );
}
