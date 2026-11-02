import { Group } from '@mantine/core';
import { EnvChip } from '@/components/EnvChip';

/** A dialog's title with where its action takes effect beside it: an annotation is a record in Shutter. */
export function DialogTitle({ children }: { children: string }) {
  return (
    <Group component="span" gap="xs" wrap="wrap">
      <span>{children}</span>
      <EnvChip />
    </Group>
  );
}
